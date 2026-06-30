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

    # Callback triggered before executing a tool call.
    property on_tool_call : Proc(String, Hash(String, JSON::Any), String, Nil)?

    # Callback triggered after executing a tool call, passing the name, arguments, result string, and status string.
    property on_tool_result : Proc(String, Hash(String, JSON::Any), String, String, Nil)?

    # The list of all available tool definitions (for generic recovery)
    property all_tools : Array(Mantle::Tools::Tool)? = nil

    # :nodoc:
    @builtin_executor : BuiltinToolExecutor?
    # :nodoc:
    @custom_callback : Proc(String, Hash(String, JSON::Any), String)?

    @client : Mantle::Clients::Client?
    @context_manager : Mantle::Storage::ContextManager?
    @recovery_config : RecoveryConfig?

    # Creates a tool executor with the specified *builtin_config*, *custom_callback*, and *bot_name*.
    def initialize(
      builtin_config : BuiltinToolConfig?,
      @custom_callback : Proc(String, Hash(String, JSON::Any), String)?,
      bot_name : String = "Assistant",
      @on_tool_call : Proc(String, Hash(String, JSON::Any), String, Nil)? = nil,
      @on_tool_result : Proc(String, Hash(String, JSON::Any), String, String, Nil)? = nil,
      @client : Mantle::Clients::Client? = nil,
      @context_manager : Mantle::Storage::ContextManager? = nil,
      @recovery_config : RecoveryConfig? = nil,
    )
      @builtin_executor = builtin_config ? BuiltinToolExecutor.new(builtin_config, bot_name) : nil
    end

    # Executes all *tool_calls* and returns their results.
    #
    # Routes each call to either the built-in executor or the custom callback.
    # Optionally uses *available_tool_names* to format helpful error messages.
    def execute_all(
      tool_calls : Array(Mantle::Clients::ToolCall),
      available_tool_names : Array(String)? = nil,
      retries : Int32? = nil,
    ) : Array(ToolResult)
      tool_calls.map do |call|
        result_json = execute_single(call, available_tool_names, retries)

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
    private def execute_single(
      tool_call : Mantle::Clients::ToolCall,
      available_tool_names : Array(String)?,
      retries : Int32? = nil,
    ) : String
      function_name = tool_call.function.name
      arguments_json = tool_call.function.arguments

      # Parse arguments
      begin
        arguments = JSON.parse(arguments_json).as_h
      rescue ex
        return {error: "Invalid arguments JSON: #{ex.message}"}.to_json
      end

      # Call start hook
      @on_tool_call.try(&.call(function_name, arguments, tool_call.id))

      actual_retries = retries || @recovery_config.try(&.max_retries) || 0

      # Route to appropriate executor
      begin
        result_json = if is_builtin_tool?(function_name)
                        execute_builtin(function_name, arguments)
                      else
                        execute_custom(function_name, arguments, available_tool_names)
                      end

        if failed_result?(result_json) && actual_retries > 0
          if recovered = attempt_recovery(tool_call, result_json, actual_retries, available_tool_names)
            result_json = recovered
          end
        end

        # Call end hook
        if hook = @on_tool_result
          status = failed_result?(result_json) ? "FAILED" : "SUCCESS"
          hook.call(function_name, arguments, result_json, status)
        end

        result_json
      rescue ex : TerminalToolInterrupt
        interrupt_ex = if ex.tool_call_id.nil?
                         TerminalToolInterrupt.new(ex.message || "", tool_call.id)
                       else
                         ex
                       end
        if hook = @on_tool_result
          hook.call(function_name, arguments, "TerminalToolInterrupt: #{ex.message}", "SUCCESS")
        end
        raise interrupt_ex
      rescue ex : TerminalToolError
        if hook = @on_tool_result
          hook.call(function_name, arguments, "TerminalToolError: #{ex.message}", "ERROR")
        end
        raise ex
      rescue ex
        err_json = {error: "Tool #{function_name} failed: #{ex.message}"}.to_json
        if failed_result?(err_json) && actual_retries > 0
          if recovered = attempt_recovery(tool_call, err_json, actual_retries, available_tool_names)
            if hook = @on_tool_result
              status = failed_result?(recovered) ? "FAILED" : "SUCCESS"
              hook.call(function_name, arguments, recovered, status)
            end
            return recovered
          end
        end
        if hook = @on_tool_result
          hook.call(function_name, arguments, err_json, "ERROR")
        end
        err_json
      end
    end

    private def attempt_recovery(
      tool_call : Mantle::Clients::ToolCall,
      error_msg : String,
      retries : Int32,
      available_tool_names : Array(String)?,
    ) : String?
      client = @client
      context_manager = @context_manager
      recovery_config = @recovery_config
      all_tools = @all_tools

      return nil unless client && context_manager && recovery_config && retries > 0

      tool_name = tool_call.function.name
      arguments_json = tool_call.function.arguments

      # 1. Parse arguments (or fall back to empty hash)
      tool_args = begin
        JSON.parse(arguments_json).as_h
      rescue
        {} of String => JSON::Any
      end

      # 2. Collect allowed tool definitions for recovery
      allowed_tool_names = [tool_name]
      if mapped = recovery_config.tool_mappings[tool_name]?
        allowed_tool_names.concat(mapped)
      end

      recovery_tools = [] of Mantle::Tools::Tool
      if all_tools
        all_tools.each do |t|
          if allowed_tool_names.includes?(t.function.name)
            recovery_tools << t
          end
        end
      end

      # 3. Ephemeral context duplication
      ephemeral_context = context_manager.current_view.dup

      # 4. Optional nudge callback
      if callback = recovery_config.on_recovery_nudge
        parsed_args = {} of String => JSON::Any
        tool_args.each do |k, v|
          parsed_args[k] = v
        end
        if nudge = callback.call(tool_name, parsed_args, error_msg)
          ephemeral_context << Mantle::Message.new("system", nudge)
        end
      end

      # 5. Generic recovery instructions prompt
      original_args_json = tool_args.to_json
      recovery_prompt = "[RECOVERY_MODE] Your previous tool call to '#{tool_name}' failed with: '#{error_msg}'. " \
                        "The original arguments were: #{original_args_json}. " \
                        "Please rectify the arguments immediately according to the schema. " \
                        "Ensure you retain all valid arguments from your previous attempt while filling in/correcting only the missing or incorrect ones. " \
                        "Do not explain your reasoning, output ONLY the corrected tool call."
      ephemeral_context << Mantle::Message.new("system", recovery_prompt)

      # 6. Execute recovery call at 0.0 temperature in a sub-loop
      orig_temp = client.temperature
      begin
        client.temperature = 0.0

        5.times do |i|
          response = client.execute(ephemeral_context, recovery_tools.empty? ? nil : recovery_tools)

          if content = response.content
            unless content.empty?
              ephemeral_context << Mantle::Message.new("assistant", content)
            end
          end

          if tool_calls = response.tool_calls
            tool_calls.each do |call|
              if call.function.name == tool_name
                res = execute_single(call, available_tool_names, retries - 1)
                unless failed_result?(res)
                  return res
                end
                ephemeral_context << Mantle::Message.new("system", "Tool result for #{tool_name}: #{res}")
              elsif mapped && mapped.includes?(call.function.name)
                res = execute_single(call, available_tool_names, 0)
                ephemeral_context << Mantle::Message.new("system", "Tool result for #{call.function.name}: #{res}")
              else
                ephemeral_context << Mantle::Message.new("system", "Error: Tool '#{call.function.name}' is not allowed in this recovery mode.")
              end
            end
          else
            nudge = "You must call the '#{tool_name}' tool with corrected arguments."
            ephemeral_context << Mantle::Message.new("system", nudge)
          end
        end
      ensure
        client.temperature = orig_temp
      end

      nil
    end

    # Helper to check if a result contains an error
    private def failed_result?(result : String) : Bool
      begin
        parsed = JSON.parse(result)
        if parsed.as_h? && parsed.as_h.has_key?("error")
          return true
        end
      rescue
        # Not valid JSON
      end
      trimmed = result.strip
      trimmed.downcase.starts_with?("error")
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
        rescue ex : TerminalToolInterrupt | TerminalToolError
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
