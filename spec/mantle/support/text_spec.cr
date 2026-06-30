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
      Mantle::Support::Text.strip_thinking(msg).should eq(" middle ")
    end

    it "returns the original string if no thinking tags are present" do
      msg = "Just a normal message"
      Mantle::Support::Text.strip_thinking(msg).should eq("Just a normal message")
    end
  end
end
