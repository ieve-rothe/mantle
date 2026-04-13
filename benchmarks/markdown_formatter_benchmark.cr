require "benchmark"
require "../src/mantle/markdown_formatter"

text = <<-'MARKDOWN'
# Heading
This is **bold** and *italic*.
Here is some `inline code` and a block:
```
code block
```
A [link](http://example.com) and a quote:
> quote
MARKDOWN

Benchmark.ips do |x|
  x.report("MarkdownFormatter.format") do
    Mantle::MarkdownFormatter.format(text)
  end
end
