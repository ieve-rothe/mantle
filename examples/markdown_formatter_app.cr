#!/usr/bin/env crystal

# Markdown Formatter Example Application
# Demonstrates Mantle's MarkdownFormatter module utility

require "../src/mantle"

puts "=" * 70
puts "Mantle Markdown Formatter Example"
puts "=" * 70
puts "This example demonstrates how a consumer application can use"
puts "Mantle::MarkdownFormatter to render an LLM response into styled ANSI output."
puts "=" * 70
puts

# Mock response from the LLM
emma_response = <<-MD
Hello! I am Emma. Here is the requested technical documentation:

# Installation

To install the dependencies, simply run the following `inline code` command:

```bash
shards install
```

# Features
- Very **fast** performance
- Written in *Crystal*
- Easy to use [Mantle Framework](https://github.com/CameronCarroll/mantle)

> Note: Make sure to read the AGENTS.md file before proceeding.

Let me know if you need any more help!
MD

puts "\e[33m--- RAW STRING (Before Formatting) ---\e[0m"
puts emma_response
puts

puts "\e[33m--- FORMATTED STRING (After Formatting) ---\e[0m"
formatted_response = Mantle::MarkdownFormatter.format(emma_response)
puts formatted_response
puts
puts "=" * 70
