# frozen_string_literal: true
require "json"
require "active_support/inflector"

version="0.7"

module JSON22d
  extend self

  def run(arr, config)
    arr = Oj.generate(arr) unless arr.is_a?(String)
    arr = JSON.parse(arr)
    fill_blanks(arr, config, &(block_given? ? Proc.new : nil))
    Enumerator.new do |y|
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
          sub_hash = v&.[](key)
          if sub_hash.is_a?(Array)
            acc = sub_hash.size if acc < sub_hash.size
          elsif !sub_hash.nil?
            acc = 1 if acc < 1
          end
          next acc
        end

        name.delete(name.keys.first)
        name["#{key}[#{max_n}]#{shift}#{unshift}"] = value
      end
      fill_blanks(values.map do |v|
        v = yield(v) if block_given?
        comment ? v : v&.[](key)
      end, value)
    end
  end

  def header(config)
    config.each_with_object([]) do |item, acc|
      process_config_item(item, acc)
    end
  end
  
  def process_config_item(item, acc)
    case item
    when Hash
      key, value = item.first
      process_hash_item(key, value, acc)
    when Array
      _, title = item
      acc << title.to_s
    else
      process_string_item(item, acc)
    end
  end
  
  def process_hash_item(key, value, acc)
    comment, key, closures, n, n2, shift, unshift, op = extract_hash_item_details(key)
    key = key.singularize
  
    if comment
      acc.concat(header(value).map { |m| "#{key}.#{m}" })
    else
      generate_header_for_hash_item(key, value, closures, n, n2, shift, unshift, op, acc)
    end
  end
  
  def extract_hash_item_details(key)
    key.to_s.match(/^(#)?([^\[(\s]+)(\[(\d+)\]|\(([^\)]+)\))?( SHIFT)?( UNSHIFT)?(\.\w+)?$/).captures
  end
  
  def generate_header_for_hash_item(key, value, closures, n, n2, shift, unshift, op, acc)
    if n
      n.to_i.times do |i|
        acc.concat(header(value).map { |m| format_header_with_index(key, m, i, shift, unshift, op) })
      end
    elsif closures.nil? || n2
      acc.concat(header(value).map { |m| format_header_without_index(key, m, shift, unshift, op) })
    end
  end
  
  def format_header_with_index(key, header, index, shift, unshift, op)
    if shift
      "#{key}[#{index}]#{header.split('.', 2).last}"
    elsif unshift
      "#{header}[#{index}]"
    elsif op
      "#{key}.#{op.split('.').last}_#{header}"
    else
      "#{key}[#{index}].#{header}"
    end
  end
  
  def format_header_without_index(key, header, shift, unshift, op)
    if shift
      "#{key}#{header.split('.', 2).last}"
    elsif unshift
      "#{header}"
    elsif op
      "#{key}.#{op.split('.').last}_#{header}"
    else
      "#{key}.#{header}"
    end
  end
  
  def process_string_item(item, acc)
    name = item.to_s.split('(', 2).first.split('+', 2).first.strip
    acc << name
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
        sub_hash = hash&.[](key)
        if comment
          acc + slice(hash, value)
        elsif n2 && sub_hash
          next acc << sub_hash.
            reduce([]) { |a, h| a + slice(h, value) }.
            join(n2)
        elsif n && (sub_hash || n.to_i == 0)
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
          next acc + slice(sub_hash, value)
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
          elsif name.include?("|")
            next acc << hash[name.split("|").detect { |k| hash[k] }]
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