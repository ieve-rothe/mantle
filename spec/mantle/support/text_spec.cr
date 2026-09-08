# spec/mantle/support/text_spec.cr
require "../../spec_helper"
require "../../../src/mantle/support/text"

describe Mantle::Support::Text do
  describe ".strip_thinking" do
    it "removes single-line thinking tags and content" do
      msg = "Hello <think>this is a thought</think> world"
      Mantle::Support::Text.strip_thinking(msg).should eq("Hello  world")
    end

    it "removes multi-line thinking tags and content" do
      msg = "Start\n<think>\nLine 1\nLine 2\n</think>\nEnd"
      Mantle::Support::Text.strip_thinking(msg).should eq("Start\n\nEnd")
    end

    it "removes multiple thinking blocks" do
      msg = "<think>first</think> middle <think>second</think>"
      Mantle::Support::Text.strip_thinking(msg).should eq("middle")
    end

    it "returns the original string if no thinking tags are present" do
      msg = "Just a normal message"
      Mantle::Support::Text.strip_thinking(msg).should eq("Just a normal message")
    end
  end

  describe ".extract_thinking" do
    it "extracts standard <think>foo</think>bar" do
      msg = "<think>foo</think>bar"
      clean, thinking = Mantle::Support::Text.extract_thinking(msg)
      clean.should eq("bar")
      thinking.should eq("foo")
    end

    it "handles multiline thinking blocks with leading/trailing newlines" do
      msg = "<think>\n  Step 1\n  Step 2\n</think>\n\nFinal Answer"
      clean, thinking = Mantle::Support::Text.extract_thinking(msg)
      clean.should eq("Final Answer")
      thinking.should eq("Step 1\n  Step 2")
    end

    it "handles incomplete / truncated <think>foo with no closing tag" do
      msg = "<think>Pondering..."
      clean, thinking = Mantle::Support::Text.extract_thinking(msg)
      clean.should eq("")
      thinking.should eq("Pondering...")
    end

    it "handles responses with no <think> tags" do
      msg = "Just a normal response"
      clean, thinking = Mantle::Support::Text.extract_thinking(msg)
      clean.should eq("Just a normal response")
      thinking.should be_nil
    end

    it "handles empty thinking tags" do
      msg = "<think></think>Clean text"
      clean, thinking = Mantle::Support::Text.extract_thinking(msg)
      clean.should eq("Clean text")
      thinking.should be_nil
    end
  end
end
