# mantle/flow.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Represents a generic LLM inference operation
#
# Base class for different LLM-based processing flows.
# Examples include planning steps, command generation, reflection, etc.

require "./tools"
require "./builtin_tools"
require "./tool_executor"
require "./tool_formatter"

module Mantle
  # Represents a generic LLM inference operation
  #
  # Base class for different LLM-based processing flows.
  # Examples include flows for planning steps, command generation, reflection, etc.
  class Flow
    property context_manager : ContextManager
    property client : Client
    property logger : Logger

    # Custom errors for flow operations
    class InputError < Exception; end

    def initialize(
      @context_manager : ContextManager,
      @client : Client,
      @logger : Logger,
    )
    end

    # Assemble context, send it to client, set model response in class
    def run(msg : String, on_response : Proc(String, Nil))
      # To be implemented by specific flows
    end

    # Convert message array to human-readable string for logging
    protected def format_messages_for_log(messages : Array(Hash(String, String))) : String
      messages.map do |msg|
        role = msg["role"].capitalize
        content = msg["content"]
        "[#{role}] #{content}\n"
      end.join
    end
  end

  class ChatFlow < Flow
    def run(msg : String, on_response : Proc(String, Nil))
      @context_manager.handle_user_message(msg)
      context_view = @context_manager.current_view
      @logger.log_message(:user, msg, format_messages_for_log(context_view))

      response = @client.execute(context_view)

      # Extract text content from Response (ignore tool_calls in base ChatFlow)
      response_text = response.content || ""

      @context_manager.handle_bot_message(response_text)
      updated_context = @context_manager.current_view
      @logger.log_message(:bot, response_text, format_messages_for_log(updated_context))

      on_response.call(response_text)
    end
  end

  # ChatFlow with tool calling support
  # Extends ChatFlow to handle tool calls in a loop until text response received
  class ToolEnabledChatFlow < ChatFlow
    DEFAULT_MAX_ITERATIONS = 10

    def run(
      msg : String,
      builtins : Array(BuiltinTool)? = nil,
      custom_tools : Array(Tool)? = nil,
      tool_callback : Proc(String, Hash(String, JSON::Any), String)? = nil,
      builtin_config : BuiltinToolConfig? = nil,
      max_iterations : Int32 = DEFAULT_MAX_ITERATIONS,
      on_response : Proc(String, Nil)? = nil
    )
      # Add user message to context
      @context_manager.handle_user_message(msg)
      context_view = @context_manager.current_view
      @logger.log_message(:user, msg, format_messages_for_log(context_view))

      # Merge tool definitions
      all_tools = merge_tools(builtins, custom_tools)

      # Create tool executor
      tool_executor = ToolExecutor.new(builtin_config, tool_callback)

      # Tool call loop
      iteration = 0
      loop do
        iteration += 1

        if iteration > max_iterations
          raise Exception.new("Max iterations (#{max_iterations}) reached in tool calling loop")
        end

        # Execute LLM with tools
        response = @client.execute(context_view, all_tools)

        # Check if we have a text response (end of loop)
        if response.content && (response.tool_calls.nil? || response.tool_calls.not_nil!.empty?)
          # Final text response
          response_text = response.content.not_nil!
          @context_manager.handle_bot_message(response_text)
          updated_context = @context_manager.current_view
          @logger.log_message(:bot, response_text, format_messages_for_log(updated_context))

          on_response.try(&.call(response_text))
          break
        end

        # We have tool calls - process them
        if tool_calls = response.tool_calls
          # Format assistant message with tool calls (natural language)
          assistant_msg = ToolFormatter.format_assistant_message_with_tool_calls(
            response.content,
            tool_calls
          )

          # Add to context
          @context_manager.handle_bot_message(assistant_msg)

          # Execute tools
          tool_results = tool_executor.execute_all(tool_calls)

          # Add tool results to context (natural language)
          tool_results.each do |result|
            formatted_result = ToolFormatter.format_tool_result(
              result.tool_call_id,
              result.result
            )
            @context_manager.handle_bot_message(formatted_result)
          end

          # Update context view for next iteration
          context_view = @context_manager.current_view

          # Log tool interaction
          @logger.log_message(:bot, "Tool calls: #{tool_calls.size}", format_messages_for_log(context_view))
        else
          # No content and no tool calls - shouldn't happen, but handle it
          response_text = ""
          @context_manager.handle_bot_message(response_text)
          on_response.try(&.call(response_text))
          break
        end
      end
    end

    # Merge built-in and custom tool definitions
    private def merge_tools(builtins : Array(BuiltinTool)?, custom : Array(Tool)?) : Array(Tool)?
      tools = [] of Tool

      # Add built-in tool definitions
      if builtins && !builtins.empty?
        tools.concat(BuiltinToolRegistry.definitions_for(builtins))
      end

      # Add custom tools
      if custom && !custom.empty?
        tools.concat(custom)
      end

      tools.empty? ? nil : tools
    end
  end
end
