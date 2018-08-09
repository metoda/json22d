# JSON to 2D a.k.a. json22d

A toolkit for JSON/Hash based results that need to be transformed into a flat
structure so they can be used in CSV or spreadsheet formats.

## Inputs and outputs

The library requires two pieces to work, an input array and a configuration.
Think of the input array like this: the configuration is applied to every
element of the array which generate result lines, all of which are appended
into an enumerator (or an array, if that helps you imagine).

Subsequently you can iterate the resulting iterator that loops through every
line generated. A line is an array again. This was built with the CSV
functionality from Ruby in mind, which takes an array of n elements and
creates a csv row from it.

As the examples below show, a configuration influences heavily how a single
result can dynamically create columns or rows, depending on how the cross
product of sub structures looks like.

Of course there is an internal logic that orders the parameters you can use
to shift, replace and aggregate results. They are applied in a convenient
order, so a combination of multiple parameters is possible.

## Integration

```ruby
require "json22d"
# insert any of the examples from below
```

With a CSV example, run it like this:

```ruby
enum = JSON22d.run(hash, config) do |h|
  # a good place to merge down content to toplevel where needed
  h.merge(h[:content])
end
enum.map { |line| CSV.generate_line(line, col_sep: ",") }
```

## Examples

### Regular fields

The most basic form of mapping data to a flat structure.

```ruby
  JSON22d.run([{"i": 3, "j": 4}, {"i": "foo"}], ["i", "j"]).to_a
  => [["i", "j"], [3, 4], ["foo", nil]]
```

### Nested fields

This is the **dig** of the library. It's used to traverse through tree
structures.

```ruby
  JSON22d.run([{"c": {"i": "foo", "j": "bar"}}], [{"c": ["i", "j"]}]).to_a
  => [["c.i", "c.j"], ["foo", "bar"]]
```

### Line multiplication

When a key within the tree structure has not a single nested structure, but
an array, these can be multiplied and create as many "lines" as the array
has elements.

```ruby
  JSON22d.run([{"c": ["foo", "bar"]}], ["c"]).to_a
  => [["c"], ["foo"], ["bar"]]
```

When a key not only leads to an array, but the array contains a nested structure
then a nested fields extraction can be used.

```ruby
  JSON22d.run([{"c": [{"i": "foo"}, {"j": "bar"}]}], [{"c": ["i"]}]).to_a
  => [["c.i"], ["foo"], ["bar"]]
```

### Field addition

When using this, the first field name is applied to the header. The delim for
the join is a space and cannot be changed.

```ruby
  JSON22d.run([{"c": {"i": "foo", "j": "bar"}}], [{"c": ["i+j"]}]).to_a
  => [["c.i"], ["foo bar"]]
```

### Field alternation

When using this, the first not-nil field is taken.
```ruby
  JSON22d.run([{"c": {"i": nil, "j": "bar"}}], [{"c": ["i|j"]}]).to_a
  => [["c.i|j"], ["bar"]]
```

### Field reduction

A key leading to an array can be also joined into a single field using a custom
delimiter.

```ruby
  JSON22d.run([{"i": ["bar", "blubb"]}, {"i": ["foo"]}], ["i(, )"]).to_a
  => [["i"], ["bar, blubb"], ["foo"]]
```

This can also be used with nested fields again, just like line multiplication
can.

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "blubb"}]}], [{"i(, )": ["j"]}]).to_a
  => [["i.j"], ["bar, blubb"]]
```

### Column multiplication

Arrays with nested fields can not only be multiplied into lines, but also into
columns.

The amount of columns can be specified or automatically detected.

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "blubb"}]}], [{"i[]": ["j"]}]).to_a
  => [["i[0].j", "i[1].j"], ["bar", "blubb"]]
```

When using a specific column amount, then the first number of array elements is
used until the amount is satisfied. The rest is disregarded.

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "blubb"}]}], [{"i[1]": ["j"]}]).to_a
  => [["i[0].j", ["bar"]]
```

### Shifting column headers down

Digging through multiple layers of the tree structure will create some rather
unreadable, long headers. One way to mitigate is shifting a layer out, removing
it from the path through the tree.

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "foo"}]}], [{"i SHIFT": ["j"]}]).to_a
  => [["i"], ["bar"], ["foo"]]
```

And with column multiplication it looks like this:

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "foo"}]}], [{"i[] SHIFT": ["j"]}]).to_a
  => [["i[0]", "i[1]"], ["bar", "foo"]]
```

### Shifting column headers up

Just like down shifting removes the rightern path entry and keeps the current
layer, shifting up keeps the rightern layer and removes the current.

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "foo"}]}], [{"i UNSHIFT": ["j"]}]).to_a
  => [["j"], ["bar"], ["foo"]]
```

And with column multiplication it looks like this:

```ruby
  JSON22d.run([{"i": [{"j": "bar"}, {"j": "foo"}]}], [{"i[] UNSHIFT": ["j"]}]).to_a
  => [["j[0]", "j[1]"], ["bar", "foo"]]
```

### Dummy headers

Sometimes a range of headers needs to be prefixed with something, and look like
it's being extracted from a sub structure.

```ruby
  JSON22d.run([{"i": "bar", "j": "foo"}], [{"#product": ["i", "j"]}]).to_a
  => [["product.i", "product.j"], ["bar", "foo"]]
```

### Renaming fields

In a time when renaming the key in your tree structure is no option, it is
possible to rename on the fly while transforming the data.

```ruby
  JSON22d.run([{"i": "bar", "j": "foo"}], ["i", ["j", "zomg"]]).to_a
  => [["i", "zomg"], ["bar", "foo"]]
```

### Aggregation of lists

Currently there is support for the functions **min**, **max** and **first**
which can be applied to lists of structures.

```ruby
  JSON22d.run([{"i": [{"j": 2}, {"j": 3}]}], [{"i.min": ["j"]}]).to_a
  => [["i.min_j"], [1]]
```
