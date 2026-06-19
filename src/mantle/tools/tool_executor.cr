# mantle/tool_executor.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../clients/client"
require "./builtin_tools"
require "json"

module Mantle::Tools
  # Represents the result of executing a tool call.
  #
  # Links the tool call ID to its execution result.
  class ToolResult
    # Represents the unique identifier of the tool call.
    property tool_call_id : String

    # Represents the raw output or result string from the tool execution.
    property result : String

    # Represents an optional natural language override for formatting the result.
    property formatted_override : String?

    # Creates a tool result mapping *tool_call_id* to *result* and optional *formatted_override*.
    def initialize(@tool_call_id : String, @result : String, @formatted_override : String? = nil)
    end
  end

  # Coordinates tool execution, routing requests to built-in or custom handlers.
  #
  # Handles both built-in tools (via `BuiltinToolExecutor`) and custom tools (via callback).
  class ToolExecutor
    # Represents the list of built-in tool names used for routing.
    BUILTIN_TOOL_NAMES = ["read_file", "list_directory", "notify_send", "write_file", "search_files"]

    # :nodoc:
    @builtin_executor : BuiltinToolExecutor?
    # :nodoc:
    @custom_callback : Proc(String, Hash(String, JSON::Any), String)?

    # Creates a tool executor with the specified *builtin_config*, *custom_callback*, and *bot_name*.
    def initialize(
      builtin_config : BuiltinToolConfig?,
      @custom_callback : Proc(String, Hash(String, JSON::Any), String)?,
      bot_name : String = "Assistant",
    )
      @builtin_executor = builtin_config ? BuiltinToolExecutor.new(builtin_config, bot_name) : nil
    end

    # Executes all *tool_calls* and returns their results.
    #
    # Routes each call to either the built-in executor or the custom callback.
    # Optionally uses *available_tool_names* to format helpful error messages.
    def execute_all(tool_calls : Array(Mantle::Clients::ToolCall), available_tool_names : Array(String)? = nil) : Array(ToolResult)
      tool_calls.map do |call|
        result_json = execute_single(call, available_tool_names)

        # Try to parse formatted_override from the result JSON
        formatted_override = nil
        begin
          parsed_result = JSON.parse(result_json)
          if parsed_result.as_h? && (override = parsed_result.as_h["formatted_override"]?)
            formatted_override = override.as_s
          end
        rescue
          # If parsing fails, just ignore and use nil
        end

        ToolResult.new(
          tool_call_id: call.id,
          result: result_json,
          formatted_override: formatted_override
        )
      end
    end

    # Execute a single tool call
    private def execute_single(tool_call : Mantle::Clients::ToolCall, available_tool_names : Array(String)?) : String
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
        execute_custom(function_name, arguments, available_tool_names)
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
    private def execute_custom(name : String, arguments : Hash(String, JSON::Any), available_tool_names : Array(String)?) : String
      if callback = @custom_callback
        begin
          callback.call(name, arguments)
        rescue ex : TerminalToolError
          raise ex
        rescue ex
          {error: "Custom tool #{name} failed: #{ex.message}"}.to_json
        end
      else
        error_msg = "Unknown tool '#{name}'."
        if available_tool_names && !available_tool_names.empty?
          error_msg += " Available tools: #{available_tool_names.join(", ")}"
        else
          error_msg += " No tools are currently available."
        end
        {error: error_msg}.to_json
      end
    end
  end
end
