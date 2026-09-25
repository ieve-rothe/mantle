require "./spec_helper"
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
      result = Mantle::Tools::ToolResult.new(
        tool_call_id: "call_123",
        result: "Success"
      )

      result.tool_call_id.should eq("call_123")
      result.result.should eq("Success")
    end
  end

  describe "execute_all with built-in tools only" do
    it "executes read_file built-in tool" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: nil
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_1",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
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
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: nil
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_2",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
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
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: nil
      )

      tool_calls = [
        Mantle::Clients::ToolCall.new(
          id: "call_1",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "list_directory",
            arguments: "{}"
          )
        ),
        Mantle::Clients::ToolCall.new(
          id: "call_2",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        ),
      ]

      results = executor.execute_all(tool_calls)

      results.size.should eq(2)
      results[0].tool_call_id.should eq("call_1")
      results[0].result.should contain("test.txt")
      results[1].tool_call_id.should eq("call_2")
      results[1].result.should contain("Test content")
    end
  end

  describe "execute_all with custom tools only" do
    it "routes to custom callback for unknown tools" do
      custom_called = false
      custom_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        custom_called = true
        %({"result":"custom_success"})
      }

      executor = Mantle::Tools::ToolExecutor.new(
        tools: [] of Mantle::Tools::Tool,
        custom_callback: custom_callback
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_custom",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "my_custom_tool",
          arguments: %({"param":"value"})
        )
      )

      results = executor.execute_all([tool_call])

      custom_called.should be_true
      results.size.should eq(1)
      results[0].tool_call_id.should eq("call_custom")
      results[0].result.should eq(%({"result":"custom_success"}))
    end

    it "passes correct arguments to custom callback" do
      received_name = ""
      received_args = {} of String => JSON::Any

      custom_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        received_name = name
        received_args = args
        "ok"
      }

      executor = Mantle::Tools::ToolExecutor.new(
        tools: [] of Mantle::Tools::Tool,
        custom_callback: custom_callback
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_args",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "greet",
          arguments: %({"name":"Alice"})
        )
      )

      results = executor.execute_all([tool_call])

      results[0].result.should contain("ok")
    end
  end

  describe "execute_all with mixed built-in and custom tools" do
    it "routes to correct executor based on tool name" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)

      custom_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        %({"custom":"result from #{name}"})
      }

      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: custom_callback
      )

      tool_calls = [
        Mantle::Clients::ToolCall.new(
          id: "call_builtin",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"test.txt"})
          )
        ),
        Mantle::Clients::ToolCall.new(
          id: "call_custom",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "my_custom_tool",
            arguments: "{}"
          )
        ),
      ]

      results = executor.execute_all(tool_calls)

      results.size.should eq(2)
      results[0].result.should contain("Test content")               # Built-in
      results[1].result.should contain("result from my_custom_tool") # Custom
    end
  end

  describe "error handling" do
    it "returns error when no callback provided for custom tool" do
      executor = Mantle::Tools::ToolExecutor.new(
        tools: [] of Mantle::Tools::Tool,
        custom_callback: nil
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_unknown",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "unknown_tool",
          arguments: "{}"
        )
      )

      results = executor.execute_all([tool_call])

      results[0].result.should contain("error")
    end

    it "continues executing remaining tools if one fails" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)

      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: nil
      )

      tool_calls = [
        Mantle::Clients::ToolCall.new(
          id: "call_fail",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
            name: "read_file",
            arguments: %({"file_path":"nonexistent.txt"})
          )
        ),
        Mantle::Clients::ToolCall.new(
          id: "call_success",
          type: "function",
          function: Mantle::Clients::ToolCallFunction.new(
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

  describe "callbacks" do
    it "triggers on_tool_call and on_tool_result for built-in tools" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)

      calls = [] of {String, Hash(String, JSON::Any)}
      results = [] of {String, Hash(String, JSON::Any), String, String}

      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: nil,
        on_tool_call: ->(name : String, args : Hash(String, JSON::Any), call_id : String) {
          calls << {name, args}
          nil
        },
        on_tool_result: ->(name : String, args : Hash(String, JSON::Any), res : String, status : String) {
          results << {name, args, res, status}
          nil
        }
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_builtin_cb",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "read_file",
          arguments: %({"file_path":"test.txt"})
        )
      )

      executor.execute_all([tool_call])

      calls.size.should eq(1)
      calls[0][0].should eq("read_file")
      calls[0][1]["file_path"].as_s.should eq("test.txt")

      results.size.should eq(1)
      results[0][0].should eq("read_file")
      results[0][2].should contain("Test content")
      results[0][3].should eq("SUCCESS")
    end

    it "triggers on_tool_call and on_tool_result with FAILED status for failed tools" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)

      results = [] of {String, Hash(String, JSON::Any), String, String}

      executor = Mantle::Tools::ToolExecutor.new(
        tools: Mantle::Tools::Builtin.all(sandbox),
        custom_callback: nil,
        on_tool_result: ->(name : String, args : Hash(String, JSON::Any), res : String, status : String) {
          results << {name, args, res, status}
          nil
        }
      )

      tool_call = Mantle::Clients::ToolCall.new(
        id: "call_builtin_fail",
        type: "function",
        function: Mantle::Clients::ToolCallFunction.new(
          name: "read_file",
          arguments: %({"file_path":"nonexistent.txt"})
        )
      )

      executor.execute_all([tool_call])

      results.size.should eq(1)
      results[0][0].should eq("read_file")
      results[0][3].should eq("FAILED")
    end
  end
end
