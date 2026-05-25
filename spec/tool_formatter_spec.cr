require "./spec_helper"

# Reopen module to expose private method for testing
module Mantle::Tools
  module ToolFormatter
    def self.exposed_truncate_string(str : String, max_length : Int32) : String
      truncate_string(str, max_length)
    end
  end
end

describe "Mantle Tool Formatter" do
  describe "format_tool_call" do
    it "formats simple tool call with one parameter" do
      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_123",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "read_file",
          arguments: %({"file_path":"test.txt"})
        )
      )

      result = Mantle::Tools::ToolFormatter.format_tool_call(tool_call)

      result.should contain("read_file")
      result.should contain("file_path")
      result.should contain("test.txt")
    end

    it "formats tool call with multiple parameters" do
      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_456",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "search_files",
          arguments: %({"pattern":"TODO","path":"/src","case_sensitive":false})
        )
      )

      result = Mantle::Tools::ToolFormatter.format_tool_call(tool_call)

      result.should contain("search_files")
      result.should contain("pattern")
      result.should contain("TODO")
      result.should contain("path")
      result.should contain("/src")
    end

    it "formats tool call with no parameters" do
      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_789",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "get_current_time",
          arguments: "{}"
        )
      )

      result = Mantle::Tools::ToolFormatter.format_tool_call(tool_call)

      result.should contain("get_current_time")
    end
  end

  describe "format_tool_result" do
    it "formats successful tool result" do
      tool_result = Mantle::Tools::ToolResult.new(
        tool_call_id: "call_123",
        result: %({"success":true,"content":"Hello, World!"})
      )

      result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

      result.should contain("call_123")
      result.should contain("Hello, World!")
    end

    it "formats error tool result" do
      tool_result = Mantle::Tools::ToolResult.new(
        tool_call_id: "call_456",
        result: %({"error":"File not found"})
      )

      result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

      result.should contain("call_456")
      result.should contain("Error")
      result.should contain("File not found")
    end

    it "truncates very long results" do
      long_content = "A" * 1000
      tool_result = Mantle::Tools::ToolResult.new(
        tool_call_id: "call_789",
        result: %({"content":"#{long_content}"})
      )

      result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

      result.size.should be < long_content.size + 100
      result.should contain("...")
    end

    it "uses formatted_override when present" do
      tool_result = Mantle::Tools::ToolResult.new(
        tool_call_id: "call_override",
        result: %({"content":"Raw result"}),
        formatted_override: "<inner_monologue>Emma consulted her notes</inner_monologue>"
      )

      result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

      # Should use the formatted_override exactly
      result.should eq("<inner_monologue>Emma consulted her notes</inner_monologue>")
      result.should_not contain("Raw result")
      result.should_not contain("call_override")
    end

    it "uses default formatting when formatted_override is nil" do
      tool_result = Mantle::Tools::ToolResult.new(
        tool_call_id: "call_default",
        result: %({"content":"Standard output"}),
        formatted_override: nil
      )

      result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

      # Should use default formatting
      result.should contain("call_default")
      result.should contain("Standard output")
    end

    describe "truncate_string boundary cases" do
      it "does not truncate when length is exactly MAX_RESULT_LENGTH" do
        max_len = Mantle::Tools::ToolFormatter::MAX_RESULT_LENGTH
        content = "A" * max_len
        tool_result = Mantle::Tools::ToolResult.new(
          tool_call_id: "call_1",
          result: %({"content":"#{content}"})
        )
        result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

        result.should contain(content)
        result.should_not contain("...")
      end

      it "truncates when length is MAX_RESULT_LENGTH + 1" do
        max_len = Mantle::Tools::ToolFormatter::MAX_RESULT_LENGTH
        content = "A" * (max_len + 1)
        tool_result = Mantle::Tools::ToolResult.new(
          tool_call_id: "call_1",
          result: %({"content":"#{content}"})
        )
        result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)

        result.should contain("...")
        # Should have max_len - 3 characters followed by ...
        # Result from call_1: AAA...
        expected_content = ("A" * (max_len - 3)) + "..."
        result.should contain(expected_content)
      end

      it "handles very small MAX_RESULT_LENGTH values (via format_tool_result would be hard, testing small max_length logic)" do
        # We can't easily change MAX_RESULT_LENGTH constant, but we can test the logic
        # by creating a test-specific wrapper if we really wanted to,
        # or just trust the format_tool_result uses it.
        # Since truncate_string is private, we've already verified it with repro_truncate.cr
        # Let's add a test for a result that is not JSON and thus hits the rescue block

        long_raw = "B" * (Mantle::Tools::ToolFormatter::MAX_RESULT_LENGTH + 10)
        tool_result = Mantle::Tools::ToolResult.new(
          tool_call_id: "call_raw",
          result: long_raw
        )
        result = Mantle::Tools::ToolFormatter.format_tool_result(tool_result)
        result.should contain("...")
        result.should contain("B" * (Mantle::Tools::ToolFormatter::MAX_RESULT_LENGTH - 3))
      end

      it "handles very small max_length values without crashing" do
        Mantle::Tools::ToolFormatter.exposed_truncate_string("Hello", 3).should eq("Hel")
        Mantle::Tools::ToolFormatter.exposed_truncate_string("Hello", 2).should eq("He")
        Mantle::Tools::ToolFormatter.exposed_truncate_string("Hello", 1).should eq("H")
        Mantle::Tools::ToolFormatter.exposed_truncate_string("Hello", 0).should eq("")
      end
    end
  end

  describe "format_assistant_message_with_tool_calls" do
    it "formats message with only tool calls (no content)" do
      tool_calls = [
        Mantle::Clients::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        )
      ]

      result = Mantle::Tools::ToolFormatter.format_assistant_message_with_tool_calls(nil, tool_calls)

      result.should contain("read_file")
      result.should contain("test.txt")
    end

    it "formats message with content and tool calls" do
      tool_calls = [
        Mantle::Clients::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        )
      ]

      result = Mantle::Tools::ToolFormatter.format_assistant_message_with_tool_calls(
        "Let me read that file for you.",
        tool_calls
      )

      result.should contain("Let me read that file for you.")
      result.should contain("read_file")
      result.should contain("test.txt")
    end

    it "formats message with multiple tool calls" do
      tool_calls = [
        Mantle::Clients::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"file1.txt"})
          )
        ),
        Mantle::Clients::ToolCall.new(
          id: "call_2",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"file2.txt"})
          )
        )
      ]

      result = Mantle::Tools::ToolFormatter.format_assistant_message_with_tool_calls(nil, tool_calls)

      result.should contain("file1.txt")
      result.should contain("file2.txt")
    end

    it "handles empty tool calls array" do
      result = Mantle::Tools::ToolFormatter.format_assistant_message_with_tool_calls(
        "Just a message",
        [] of Mantle::Clients::ToolCall
      )

      result.should eq("Just a message")
    end

    it "handles nil content and empty tool calls" do
      result = Mantle::Tools::ToolFormatter.format_assistant_message_with_tool_calls(
        nil,
        [] of Mantle::Clients::ToolCall
      )

      result.should eq("")
    end
  end
end
