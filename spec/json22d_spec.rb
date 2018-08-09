# frozen_string_literal: true
require "minitest/autorun"
require "minitest/spec"
require "json22d"

describe "JSON22d" do
  after do
    @arr = @config = nil
  end
  describe "fill missing ranges" do
    before do
      @arr = [
        {"a": [{"i": 1}, {"i": 3}, {"i": 6}]},
        {"a": [{"i": 2}, {"i": 4}]}
      ]
      @config = ["a[]": %w(i)]
    end

    it "inserts the maximum array length into the header as fields" do
      enum = JSON22d.run(@arr, @config)
      assert_equal 3, enum.next.size
    end

    it "uses an iteration index for each generated header" do
      enum = JSON22d.run(@arr, @config)
      header = enum.next
      3.times.each do |i|
        assert_equal "a[#{i}].i", header[i]
      end
    end
  end

  describe "extract regular fields" do
    before do
      @arr = [{"i": 3, "j": 4}, {"i": "foo"}]
      @config = %w(i j)
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["i", "j"], header
    end

    it "extracts the data in correct order" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal [3, 4], enum.next
      assert_equal ["foo", nil], enum.next
    end
  end

  describe "extract nested fields" do
    before do
      @arr = ["content": {"i": "foo"}]
      @config = ["content": %w(i)]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["content.i"], header
    end

    it "extracts the data in correct order" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["foo"], enum.next
    end
  end

  describe "simulate nested field in header" do
    before do
      @arr = ["content": "foo"]
      @config = ["#my": %w(content)]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["my.content"], header
    end

    it "extracts the data while skipping simulated headers" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["foo"], enum.next
    end
  end

  describe "multiplies fields within arrays" do
    before do
      @arr = ["content": ["bar", "foo"]]
      @config = ["content"]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["content"], header
    end

    it "extracts the data in correct order" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar"], enum.next
      assert_equal ["foo"], enum.next
    end
  end

  describe "multiplies nested fields within arrays" do
    before do
      @arr = ["content": [{"i": "bar"}, {"i": "foo"}]]
      @config = ["content": %w(i)]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["content.i"], header
    end

    it "extracts the data in correct order" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar"], enum.next
      assert_equal ["foo"], enum.next
    end
  end

  describe "joins two field results with a space" do
    before do
      @arr = [{"i": "bar", "j": "foo"}]
      @config = %w(i+j)
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["i"], header
    end

    it "extracts and joins the two fields" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar foo"], enum.next
    end
  end

  describe "selects first not-nil from two field results" do
    before do
      @arr = [{"i": "bar", "j": "foo"}]
      @config = %w(i|j)
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["i|j"], header
    end

    it "extracts the first of two fields" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar"], enum.next
    end

    it "extracts the second of two fields" do
      @arr.first.delete(:i)
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["foo"], enum.next
    end
  end

  describe "joins multiple values within subarrays with given delim" do
    before do
      @arr = [{"i": ["bar", "blubb"]}, {"i": ["foo"]}]
      @config = ["i( , )"]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["i"], header
    end

    it "extracts and joins the arrays" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar , blubb"], enum.next
      assert_equal ["foo"], enum.next
    end
  end

  describe "joins multiple values after applying nested fields" do
    before do
      @arr = [{"i": [{"j": "bar"}, {"j": "blubb"}]}]
      @config = ["i( , )": %w(j)]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["i.j"], header
    end

    it "extracts and joins the arrays" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar , blubb"], enum.next
    end
  end

  describe "multiplies nested array into header" do
    before do
      @arr = ["content": [{"i": "bar"}, {"i": "foo"}]]
      @config = ["content[]": %w(i)]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["content[0].i", "content[1].i"], header
    end

    it "extracts the data in correct order" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar", "foo"], enum.next
    end
  end

  describe "multiplies nested array into header with range" do
    before do
      @arr = ["content": [{"i": "bar"}, {"i": "foo"}]]
      @config = ["content[1]": %w(i)]
    end

    it "sets the correct header" do
      header = JSON22d.run(@arr, @config).next
      assert_equal ["content[0].i"], header
    end

    it "extracts the data up to range" do
      enum = JSON22d.run(@arr, @config)
      enum.next # throw away header
      assert_equal ["bar"], enum.next
    end
  end

  describe "shift nested name down in header" do
    before do
      @arr = ["content": [{"i": {"j":"bar"}}, {"i": {"j": "foo"}}]]
    end

    it "shifts j out for line multiplication" do
      header = JSON22d.run(@arr, ["content": ["i SHIFT": %w(j)]]).next
      assert_equal ["content.i"], header
    end

    it "shifts j out for column multiplication" do
      header = JSON22d.run(@arr, ["content": ["i[] SHIFT": %w(j)]]).next
      assert_equal ["content.i[0]"], header
    end

    it "shifts i out for line multiplication" do
      header = JSON22d.run(@arr, ["content[] SHIFT": ["i": %w(j)]]).next
      assert_equal ["content[0].j", "content[1].j"], header
    end

    it "shifts i out for column multiplication but keeps brackets" do
      header = JSON22d.run(@arr, ["content[] SHIFT": ["i[]": %w(j)]]).next
      assert_equal ["content[0][0].j", "content[1][0].j"], header
    end
  end

  describe "shift nested name up in header" do
    before do
      @arr = ["content": [{"i": {"j":"bar"}}, {"i": {"j": "foo"}}]]
    end

    it "shifts content out for line multiplication" do
      header = JSON22d.run(@arr, ["content UNSHIFT": ["i": %w(j)]]).next
      assert_equal ["i.j"], header
    end

    it "shifts content out for column multiplication" do
      header = JSON22d.run(@arr, ["content UNSHIFT": ["i[]": %w(j)]]).next
      assert_equal ["i[0].j"], header
    end

    it "shifts j out for line multiplication" do
      header = JSON22d.run(@arr, ["content[]": ["i UNSHIFT": %w(j)]]).next
      assert_equal ["content[0].j", "content[1].j"], header
    end

    it "shifts j out for column multiplication but keeps brackets" do
      header = JSON22d.run(@arr, ["content[]": ["i[] UNSHIFT": %w(j)]]).next
      assert_equal ["content[0].j[0]", "content[1].j[0]"], header
    end
  end

  {
    min: 1,
    max: 3,
    first: 2
  }.each do |op, val|
    describe "extract value by aggregator" do
      before do
        @arr = [{"content": [{"i": 2}, {"i": 3}, {"i": 1}]}]
      end

      it "generates the correct header for #{op}" do
        header = JSON22d.run(@arr, ["content.#{op}": ["i"]]).next
        assert_equal ["content.#{op}_i"], header
      end

      it "extracts the #{op} value from i" do
        enum = JSON22d.run(@arr, ["content.#{op}": ["i"]])
        enum.next # throw away header
        assert_equal [val], enum.next
      end
    end
  end
end
