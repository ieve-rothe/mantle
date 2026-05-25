require "benchmark"
require "../src/mantle"

text = <<-MARKDOWN
# Header 1
This is **bold** and this is *italic*.
Here is some `inline code`.
> This is a blockquote.
[Link](https://example.com)

```crystal
def hello
  puts "world"
end
```

## Header 2
Another **bold** and *italic* example.
MARKDOWN

puts "Benchmarking MarkdownFormatter.format..."
Benchmark.bm do |x|
  x.report("format") do
    10_000.times do
      Mantle::Support::MarkdownFormatter.format(text)
    end
  end
end
