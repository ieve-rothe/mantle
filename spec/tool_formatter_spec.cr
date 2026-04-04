require "./spec_helper"
require "../src/mantle/client"
require "../src/mantle/tool_formatter"

describe "Mantle Tool Formatter" do
  describe "format_tool_call" do
    it "formats simple tool call with one parameter" do
      tool_call = Mantle::ToolCall.new(
        id: "call_123",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "read_file",
          arguments: %({"file_path":"test.txt"})
        )
      )

      result = Mantle::ToolFormatter.format_tool_call(tool_call)

      result.should contain("read_file")
      result.should contain("file_path")
      result.should contain("test.txt")
    end

    it "formats tool call with multiple parameters" do
      tool_call = Mantle::ToolCall.new(
        id: "call_456",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "search_files",
          arguments: %({"pattern":"TODO","path":"/src","case_sensitive":false})
        )
      )

      result = Mantle::ToolFormatter.format_tool_call(tool_call)

      result.should contain("search_files")
      result.should contain("pattern")
      result.should contain("TODO")
      result.should contain("path")
      result.should contain("/src")
    end

    it "formats tool call with no parameters" do
      tool_call = Mantle::ToolCall.new(
        id: "call_789",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "get_current_time",
          arguments: "{}"
        )
      )

      result = Mantle::ToolFormatter.format_tool_call(tool_call)

      result.should contain("get_current_time")
    end
  end

  describe "format_tool_result" do
    it "formats successful tool result" do
      result = Mantle::ToolFormatter.format_tool_result(
        "call_123",
        %({"success":true,"content":"Hello, World!"})
      )

      result.should contain("call_123")
      result.should contain("Hello, World!")
    end

    it "formats error tool result" do
      result = Mantle::ToolFormatter.format_tool_result(
        "call_456",
        %({"error":"File not found"})
      )

      result.should contain("call_456")
      result.should contain("Error")
      result.should contain("File not found")
    end

    it "truncates very long results" do
      long_content = "A" * 1000
      result = Mantle::ToolFormatter.format_tool_result(
        "call_789",
        %({"content":"#{long_content}"})
      )

      result.size.should be < long_content.size + 100
      result.should contain("...")
    end
  end

  describe "format_assistant_message_with_tool_calls" do
    it "formats message with only tool calls (no content)" do
      tool_calls = [
        Mantle::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        )
      ]

      result = Mantle::ToolFormatter.format_assistant_message_with_tool_calls(nil, tool_calls)

      result.should contain("read_file")
      result.should contain("test.txt")
    end

    it "formats message with content and tool calls" do
      tool_calls = [
        Mantle::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        )
      ]

      result = Mantle::ToolFormatter.format_assistant_message_with_tool_calls(
        "Let me read that file for you.",
        tool_calls
      )

      result.should contain("Let me read that file for you.")
      result.should contain("read_file")
      result.should contain("test.txt")
    end

    it "formats message with multiple tool calls" do
      tool_calls = [
        Mantle::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"file1.txt"})
          )
        ),
        Mantle::ToolCall.new(
          id: "call_2",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"file2.txt"})
          )
        )
      ]

      result = Mantle::ToolFormatter.format_assistant_message_with_tool_calls(nil, tool_calls)

      result.should contain("file1.txt")
      result.should contain("file2.txt")
    end

    it "handles empty tool calls array" do
      result = Mantle::ToolFormatter.format_assistant_message_with_tool_calls(
        "Just a message",
        [] of Mantle::ToolCall
      )

      result.should eq("Just a message")
    end

    it "handles nil content and empty tool calls" do
      result = Mantle::ToolFormatter.format_assistant_message_with_tool_calls(
        nil,
        [] of Mantle::ToolCall
      )

      result.should eq("")
    end
  end
end
