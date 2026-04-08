require "spec"
require "../src/mantle/markdown_formatter"

describe Mantle::MarkdownFormatter do
  it "formats bold text" do
    result = Mantle::MarkdownFormatter.format("This is **bold** text")
    result.should eq("This is \e[1;97mbold\e[0m text")
  end

  it "formats italic text" do
    result = Mantle::MarkdownFormatter.format("This is *italic* text")
    result.should eq("This is \e[3mitalic\e[0m text")
  end

  it "formats multi-line code blocks" do
    result = Mantle::MarkdownFormatter.format("```ruby\nputs 'hello'\n```")
    result.should eq("\e[48;5;236mruby\nputs 'hello'\n\e[0m")
  end

  it "formats inline code" do
    result = Mantle::MarkdownFormatter.format("Here is `code`")
    result.should eq("Here is \e[48;5;236mcode\e[0m")
  end

  it "formats headers" do
    result = Mantle::MarkdownFormatter.format("# Header 1")
    result.should eq("\e[1;36m# Header 1\e[0m")
  end

  it "formats links" do
    result = Mantle::MarkdownFormatter.format("A [link](http://example.com)")
    result.should eq("A \e[34mlink\e[0m (\e[4;34mhttp://example.com\e[0m)")
  end

  it "formats blockquotes" do
    result = Mantle::MarkdownFormatter.format("> Quote here")
    result.should eq("\e[3;90m> Quote here\e[0m")
  end

  it "handles multiple formats in a single string" do
    text = "Here is **bold** and `code`"
    result = Mantle::MarkdownFormatter.format(text)
    result.should eq("Here is \e[1;97mbold\e[0m and \e[48;5;236mcode\e[0m")
  end
end
