require "./client"
require "./builtin_tools"
require "json"

module Mantle
  # Result from executing a tool
  # Links the tool call ID to its execution result
  class ToolResult
    property tool_call_id : String
    property result : String

    def initialize(@tool_call_id : String, @result : String)
    end
  end

  # Coordinates tool execution, routing to built-in or custom handlers
  # Handles both built-in tools (via BuiltinToolExecutor) and custom tools (via callback)
  class ToolExecutor
    # List of built-in tool names for routing
    BUILTIN_TOOL_NAMES = ["read_file", "list_directory"]

    @builtin_executor : BuiltinToolExecutor?
    @custom_callback : Proc(String, Hash(String, JSON::Any), String)?

    def initialize(
      builtin_config : BuiltinToolConfig?,
      @custom_callback : Proc(String, Hash(String, JSON::Any), String)?
    )
      @builtin_executor = builtin_config ? BuiltinToolExecutor.new(builtin_config) : nil
    end

    # Execute all tool calls and return their results
    # Routes each call to either built-in executor or custom callback
    def execute_all(tool_calls : Array(ToolCall)) : Array(ToolResult)
      tool_calls.map do |call|
        result_json = execute_single(call)
        ToolResult.new(
          tool_call_id: call.id,
          result: result_json
        )
      end
    end

    # Execute a single tool call
    private def execute_single(tool_call : ToolCall) : String
      function_name = tool_call.function.name
      arguments_json = tool_call.function.arguments

      # Parse arguments
      begin
        arguments = JSON.parse(arguments_json).as_h
      rescue ex
        return {error: "Invalid arguments JSON: #{ex.message}"}.to_json
      end

      # Route to appropriate executor
      if is_builtin_tool?(function_name)
        execute_builtin(function_name, arguments)
      else
        execute_custom(function_name, arguments)
      end
    end

    # Check if a tool name is a built-in tool
    private def is_builtin_tool?(name : String) : Bool
      BUILTIN_TOOL_NAMES.includes?(name)
    end

    # Execute a built-in tool
    private def execute_builtin(name : String, arguments : Hash(String, JSON::Any)) : String
      if executor = @builtin_executor
        executor.execute(name, arguments)
      else
        {error: "Built-in tool #{name} requested but no builtin_config provided"}.to_json
      end
    end

    # Execute a custom tool via callback
    private def execute_custom(name : String, arguments : Hash(String, JSON::Any)) : String
      if callback = @custom_callback
        begin
          callback.call(name, arguments)
        rescue ex
          {error: "Custom tool #{name} failed: #{ex.message}"}.to_json
        end
      else
        {error: "Unknown tool '#{name}' - not a built-in tool and no custom tool handler provided"}.to_json
      end
    end
  end
end
