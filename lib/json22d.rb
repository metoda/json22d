# frozen_string_literal: true
require "json"
require "active_support/inflector"

module JSON22d
  extend self

  VERSION = "0.2"

  def run(arr, config)
    arr = arr.to_json unless arr.is_a?(String)
    arr = JSON.parse(arr)
    fill_blanks(arr, config, &(block_given? ? Proc.new : nil))
    return Enumerator.new do |y|
      y << header(config)
      arr.each do |h|
        row(block_given? ? yield(h) : h, config).each { |r| y << r }
      end
    end
  end

  private

  def fill_blanks(values, config)
    values = values.first if values.is_a?(Array) && values.size == 1
    values = [values] unless values.is_a?(Array)
    subconfig = config.select { |c| c.is_a?(Hash) }
    subconfig.each do |name|
      key, value = name.first
      comment, key, no_n, shift, unshift = key.to_s.
        match(/^(#)?([^\[]+?)(\[\])?( SHIFT)?( UNSHIFT)?$/)&.
        captures
      if no_n
        max_n = values.reduce(0) do |acc, v|
          v = yield(v) if block_given?
          sub_hash = v[key]
          if sub_hash.is_a?(Array)
            acc = sub_hash.count if acc < sub_hash.count
          else
            acc = 1 if acc < 1
          end
          next acc
        end

        name.delete(name.keys.first)
        name["#{key}[#{max_n}]#{shift}#{unshift}"] = value
      end
      fill_blanks(values.map do |v|
        v = yield(v) if block_given?
        comment ? v : v[key]
      end, value)
    end
  end

  def header(config)
    return config.reduce([]) do |acc, name|
      if name.is_a?(Hash)
        key, value = name.first
        comment, key, closures, n, n2, shift, unshift = key.to_s.
          match(/^(#)?([^\[(\s]+)(\[(\d+)\]|\(([^\)]+)\))?( SHIFT)?( UNSHIFT)?$/)&.
          captures
        key, op = key.split(".")
        key = key.singularize
        if comment
          acc + header(value).map { |m| "#{key}.#{m}" }
        elsif n
          next acc + n.to_i.times.reduce([]) do |a, i|
            a + header(value).map do |m|
              if shift
                "#{key}[#{i}]#{m.match(/^[^(\[\s\.]+(.*)$/)&.captures&.first}"
              elsif unshift
                "#{m}[#{i}]"
              elsif op
                "#{key}.#{op}_#{m}"
              else
                "#{key}[#{i}].#{m}"
              end
            end
          end
        elsif closures.nil? || n2
          next acc + header(value).map do |m|
            if shift
              "#{key}#{m.match(/^[^(\[\s\.]+(.*)$/)&.captures&.first}"
            elsif unshift
              "#{m}"
            elsif op
              "#{key}.#{op}_#{m}"
            else
              "#{key}.#{m}"
            end
          end
        else
          # "pos" is the column for determining i.e. offer position in a product
          next acc + (["pos"] + header(value)).map do |m|
            if shift
              "#{key}#{m.match(/^[^(\[\s\.]+(.*)$/)&.captures&.first}"
            elsif unshift
              "#{m}"
            elsif op
              "#{key}.#{op}_#{m}"
            else
              "#{key}.#{m}"
            end
          end
        end
      elsif name.is_a?(Array)
        _key, title = name
        next acc << title.to_s
      else
        name, *_ = name.to_s.match(/^([^(]+)(\(([^\)]+)\))?$/)&.captures
        name = name.match(/^([^+]+)/).captures.first
        next acc << name.to_s
      end
    end
  end

  def row(hash, config)
    multiply(slice(hash, config))
  end

  def multiply(array, result = [[]])
    array = [array] unless array.is_a?(Array)
    array.each do |elem|
      if elem.is_a?(Array)
        result = elem.reduce([]) { |a, e| a + multiply(e, result.map(&:dup)) }
      else
        result = result.map { |r| r << elem }
      end
    end
    return result
  end

  def slice(hash, config)
    return config.reduce([]) do |acc, name|
      if name.is_a?(Hash)
        key, value = name.first
        comment, key, closures, n, n2, _shift, _unshift = key.to_s.
          match(/^(#)?([^\[(\s]+)(\[(\d+)\]|\(([^\)]+)\))?( SHIFT)?( UNSHIFT)?$/)&.
          captures
        key, op = key.split(".")
        sub_hash = hash[key]
        if comment
          acc + slice(hash, value)
        elsif n2 && sub_hash
          next acc << sub_hash.
            reduce([]) { |a, h| a + slice(h, value) }.
            join(n2)
        elsif n && sub_hash
          next acc + n.to_i.times.map { |i| sub_hash[i] }.
            reduce([]) { |a, h| a + slice(h, value) }
        elsif sub_hash.is_a?(Array)
          # [i] is the "pos" column
          next acc << [slice({}, value)] if sub_hash.empty?
          next acc << sub_hash.map.
            with_index do |h, i|
              (closures.nil? ? [] : [i]) + slice(h, value)
            end.reduce(nil, &with_op(op))
        else
          # [1] is the "pos" column
          next acc + (closures.nil? ? [] : [1]) + slice(sub_hash, value)
        end
      else
        if hash.nil?
          next acc << hash
        else
          name, _title = name if name.is_a?(Array)
          name, closures, n = name.to_s.
            match(/^([^(]+)(\(([^\)]+)\))?$/)&.captures
          sub_array = hash[name]
          if sub_array.is_a?(Array)
            sub_array = sub_array.map(&method(:sprintf))
          else
            sub_array = sprintf(sub_array)
          end
          if name.include?("+")
            next acc << name.split("+").map { |k| hash[k] }.compact.join(" ")
          elsif n && sub_array.is_a?(Array)
            next acc << sub_array.join(n)
          else
            next acc << sub_array
          end
        end
      end
    end
  end

  def with_op(op)
    if op
      case op
      when "min"
        ->(a, e) do
          e = e.first if e.is_a?(Array)
          ef = e.to_f
          af = a&.to_f
          (af || ef) > ef ? e : (a || e)
        end
      when "max"
        ->(a, e) do
          e = e.first if e.is_a?(Array)
          ef = e.to_f
          af = a&.to_f
          (af || 0) < ef ? e : a
        end
      when "first"
        ->(a, e) do
          e = e.first if e.is_a?(Array)
          a || e
        end
      end
    else
      return ->(a, e) { (a || []) << e }
    end
  end

  def sprintf(value)
    if !value.respond_to?(:strftime) &&
       value !~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/
      return value
    end
    value = Time.parse(value) if !value.respond_to?(:strftime)
    return value.strftime("%Y-%m-%d %H:%M:%S %Z")
  end
end
