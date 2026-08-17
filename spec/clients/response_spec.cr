# spec/clients/response_spec.cr
require "../spec_helper"
require "json"

describe Mantle::Clients::Response do
  describe "completion metadata and truncation helpers" do
    it "initializes with default nil metadata" do
      response = Mantle::Clients::Response.new(content: "hello", tool_calls: nil)
      response.done_reason.should be_nil
      response.prompt_eval_count.should be_nil
      response.eval_count.should be_nil
      response.truncated?.should be_false
      response.thinking_only?.should be_false
      response.truncated_in_thinking?.should be_false
    end

    it "identifies truncated responses when done_reason is length" do
      response = Mantle::Clients::Response.new(
        content: "partial text...",
        tool_calls: nil,
        done_reason: "length",
        prompt_eval_count: 50,
        eval_count: 2500
      )
      response.done_reason.should eq("length")
      response.prompt_eval_count.should eq(50)
      response.eval_count.should eq(2500)
      response.truncated?.should be_true
      response.thinking_only?.should be_false
      response.truncated_in_thinking?.should be_false
    end

    it "identifies thinking_only responses when only thinking tokens exist" do
      response = Mantle::Clients::Response.new(
        content: nil,
        tool_calls: nil,
        thinking: "Let me ponder this problem...",
        done_reason: "stop"
      )
      response.thinking_only?.should be_true
      response.truncated?.should be_false
      response.truncated_in_thinking?.should be_true
    end

    it "identifies truncated_in_thinking when token limit is hit during thinking" do
      response = Mantle::Clients::Response.new(
        content: nil,
        tool_calls: nil,
        thinking: "Thinking deeply but running out of budget...",
        done_reason: "length",
        prompt_eval_count: 100,
        eval_count: 2500
      )
      response.truncated?.should be_true
      response.thinking_only?.should be_true
      response.truncated_in_thinking?.should be_true
    end

    it "returns false for thinking_only when tool calls are present" do
      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_1",
        function: Mantle::Clients::ToolCallFunction.new("test_tool", "{}")
      )
      response = Mantle::Clients::Response.new(
        content: nil,
        tool_calls: [tool_call],
        thinking: "Calling a tool now...",
        done_reason: "stop"
      )
      response.thinking_only?.should be_false
      response.truncated_in_thinking?.should be_false
    end

    it "serializes and deserializes metadata correctly via JSON" do
      response = Mantle::Clients::Response.new(
        content: "Result",
        tool_calls: nil,
        thinking: "Thought",
        done_reason: "stop",
        prompt_eval_count: 120,
        eval_count: 45
      )

      json = response.to_json
      deserialized = Mantle::Clients::Response.from_json(json)

      deserialized.content.should eq("Result")
      deserialized.thinking.should eq("Thought")
      deserialized.done_reason.should eq("stop")
      deserialized.prompt_eval_count.should eq(120)
      deserialized.eval_count.should eq(45)
    end
  end
end
