require "./spec_helper"
require "../src/mantle/client"
require "../src/mantle/builtin_tools"
require "../src/mantle/tool_executor"
require "file_utils"

describe "Mantle Tool Executor" do
  # Setup test environment
  temp_dir = "/tmp/mantle_executor_test_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}"

  before_all do
    Dir.mkdir_p(temp_dir)
    File.write("#{temp_dir}/test.txt", "Test content")
  end

  after_all do
    FileUtils.rm_rf(temp_dir)
  end

  describe "ToolResult" do
    it "can be created with tool_call_id and result" do
      result = Mantle::ToolResult.new(
        tool_call_id: "call_123",
        result: "Success"
      )

      result.tool_call_id.should eq("call_123")
      result.result.should eq("Success")
    end
  end

  describe "execute_all with built-in tools only" do
    it "executes read_file built-in tool" do
      config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
      executor = Mantle::ToolExecutor.new(
        builtin_config: config,
        custom_callback: nil
      )

      tool_call = Mantle::ToolCall.new(
        id: "call_1",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "read_file",
          arguments: %({"file_path":"test.txt"})
        )
      )

      results = executor.execute_all([tool_call])

      results.size.should eq(1)
      results[0].tool_call_id.should eq("call_1")
      results[0].result.should contain("Test content")
    end

    it "executes list_directory built-in tool" do
      config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
      executor = Mantle::ToolExecutor.new(
        builtin_config: config,
        custom_callback: nil
      )

      tool_call = Mantle::ToolCall.new(
        id: "call_2",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "list_directory",
          arguments: "{}"
        )
      )

      results = executor.execute_all([tool_call])

      results.size.should eq(1)
      results[0].tool_call_id.should eq("call_2")
      results[0].result.should contain("test.txt")
    end

    it "executes multiple built-in tool calls" do
      config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
      executor = Mantle::ToolExecutor.new(
        builtin_config: config,
        custom_callback: nil
      )

      tool_calls = [
        Mantle::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "list_directory",
            arguments: "{}"
          )
        ),
        Mantle::ToolCall.new(
          id: "call_2",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        ),
      ]

      results = executor.execute_all(tool_calls)

      results.size.should eq(2)
      results[0].tool_call_id.should eq("call_1")
      results[1].tool_call_id.should eq("call_2")
    end
  end

  describe "execute_all with custom tools only" do
    it "executes custom tool via callback" do
      custom_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        if name == "get_time"
          %({"time":"12:00:00"})
        else
          %({"error":"Unknown tool"})
        end
      }

      executor = Mantle::ToolExecutor.new(
        builtin_config: nil,
        custom_callback: custom_callback
      )

      tool_call = Mantle::ToolCall.new(
        id: "call_custom",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "get_time",
          arguments: "{}"
        )
      )

      results = executor.execute_all([tool_call])

      results.size.should eq(1)
      results[0].tool_call_id.should eq("call_custom")
      results[0].result.should contain("12:00:00")
    end

    it "passes arguments to custom callback" do
      custom_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        if name == "greet"
          person = args["name"].as_s
          %({"message":"Hello, #{person}!"})
        else
          %({"error":"Unknown tool"})
        end
      }

      executor = Mantle::ToolExecutor.new(
        builtin_config: nil,
        custom_callback: custom_callback
      )

      tool_call = Mantle::ToolCall.new(
        id: "call_greet",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "greet",
          arguments: %({"name":"Alice"})
        )
      )

      results = executor.execute_all([tool_call])

      results[0].result.should contain("Hello, Alice!")
    end
  end

  describe "execute_all with mixed built-in and custom tools" do
    it "routes to correct executor based on tool name" do
      config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)

      custom_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        %({"custom":"result from #{name}"})
      }

      executor = Mantle::ToolExecutor.new(
        builtin_config: config,
        custom_callback: custom_callback
      )

      tool_calls = [
        Mantle::ToolCall.new(
          id: "call_builtin",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        ),
        Mantle::ToolCall.new(
          id: "call_custom",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "my_custom_tool",
            arguments: "{}"
          )
        ),
      ]

      results = executor.execute_all(tool_calls)

      results.size.should eq(2)
      results[0].result.should contain("Test content")      # Built-in
      results[1].result.should contain("result from my_custom_tool") # Custom
    end
  end

  describe "error handling" do
    it "returns error when no callback provided for custom tool" do
      executor = Mantle::ToolExecutor.new(
        builtin_config: nil,
        custom_callback: nil
      )

      tool_call = Mantle::ToolCall.new(
        id: "call_unknown",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "unknown_tool",
          arguments: "{}"
        )
      )

      results = executor.execute_all([tool_call])

      results[0].result.should contain("error")
    end

    it "continues executing remaining tools if one fails" do
      config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)

      executor = Mantle::ToolExecutor.new(
        builtin_config: config,
        custom_callback: nil
      )

      tool_calls = [
        Mantle::ToolCall.new(
          id: "call_fail",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"nonexistent.txt"})
          )
        ),
        Mantle::ToolCall.new(
          id: "call_success",
          type: "function",
          function: Mantle::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        ),
      ]

      results = executor.execute_all(tool_calls)

      results.size.should eq(2)
      results[0].result.should contain("error")
      results[1].result.should contain("Test content")
    end
  end
end
