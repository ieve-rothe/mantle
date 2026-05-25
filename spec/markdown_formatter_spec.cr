require "./spec_helper"

describe Mantle::Support::MarkdownFormatter do
  it "formats bold text" do
    result = Mantle::Support::MarkdownFormatter.format("This is **bold** text")
    result.should eq("This is \e[1;97mbold\e[0m text")
  end

  it "formats italic text" do
    result = Mantle::Support::MarkdownFormatter.format("This is *italic* text")
    result.should eq("This is \e[3mitalic\e[0m text")
  end

  it "formats multi-line code blocks" do
    result = Mantle::Support::MarkdownFormatter.format("```ruby\nputs 'hello'\n```")
    result.should eq("\e[48;5;236mruby\nputs 'hello'\n\e[0m")
  end

  it "formats inline code" do
    result = Mantle::Support::MarkdownFormatter.format("Here is `code`")
    result.should eq("Here is \e[48;5;236mcode\e[0m")
  end

  it "formats headers" do
    result = Mantle::Support::MarkdownFormatter.format("# Header 1")
    result.should eq("\e[1;36m# Header 1\e[0m")
  end

  it "formats links" do
    result = Mantle::Support::MarkdownFormatter.format("A [link](http://example.com)")
    result.should eq("A \e[34mlink\e[0m (\e[4;34mhttp://example.com\e[0m)")
  end

  it "formats blockquotes" do
    result = Mantle::Support::MarkdownFormatter.format("> Quote here")
    result.should eq("\e[3;90m> Quote here\e[0m")
  end

  it "handles multiple formats in a single string" do
    text = "Here is **bold** and `code`"
    result = Mantle::Support::MarkdownFormatter.format(text)
    result.should eq("Here is \e[1;97mbold\e[0m and \e[48;5;236mcode\e[0m")
  end

  it "handles nested formatting in blockquotes" do
    text = "> This is **bold** in a blockquote"
    result = Mantle::Support::MarkdownFormatter.format(text)
    result.should eq("\e[3;90m> This is \e[1;97mbold\e[0m in a blockquote\e[0m")
  end

  it "handles bold within headers" do
    text = "# Header with **bold**"
    result = Mantle::Support::MarkdownFormatter.format(text)
    result.should eq("\e[1;36m# Header with \e[1;97mbold\e[0m\e[0m")
  end
end
