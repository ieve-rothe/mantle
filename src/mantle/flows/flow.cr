# mantle/flow.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Represents a generic LLM inference operation
#
# Base class for different LLM-based processing flows.
# Examples include planning steps, command generation, reflection, etc.

require "../tools/tools"
require "../tools/builtin_tools"
require "../tools/tool_executor"
require "../tools/tool_formatter"

module Mantle::Flows
  # Represents a generic LLM inference operation.
  #
  # Base class for different LLM-based processing flows.
  # Examples include flows for planning steps, command generation, reflection, etc.
  class Flow
    # Represents the `ContextManager` coordinating context for the flow.
    property context_manager : Mantle::Storage::ContextManager

    # Represents the `Client` executing LLM requests.
    property client : Mantle::Clients::Client

    # Represents the `Logger` logging conversation events.
    property logger : Mantle::Support::Logger

    # Represents custom errors for flow operations.
    class InputError < Exception; end

    # Creates a flow instance with *context_manager*, *client*, and *logger*.
    def initialize(
      @context_manager : Mantle::Storage::ContextManager,
      @client : Mantle::Clients::Client,
      @logger : Mantle::Support::Logger,
    )
    end

    # Assembles context, sends it to the client, and executes *on_response* with the result.
    def run(msg : String, on_response : Proc(Mantle::Clients::Response, Nil), ephemeral_blocks : Array(String) = [] of String)
      raise NotImplementedError.new("Flow#run must be implemented by subclasses")
    end

    # :nodoc:
    protected def format_messages_for_log(messages : Array(Hash(String, String))) : String
      String.build do |io|
        messages.join(io, "") do |msg, i|
          role = msg["role"].capitalize
          content = msg["content"]
          i << "[" << role << "] " << content << "\n"
        end
      end
    end
  end

  # Represents a standard chat-based LLM flow without tool execution capabilities.
  class ChatFlow < Flow
    # Runs the chat flow by sending conversation messages to the client and handling the response.
    #
    # Custom callback *on_response* is executed with the final `Response` payload.
    def run(msg : String, on_response : Proc(Mantle::Clients::Response, Nil), ephemeral_blocks : Array(String) = [] of String, invisible_append : String? = nil)
      @context_manager.handle_user_message(msg, invisible_append)
      context_view = @context_manager.current_view(ephemeral_blocks)
      @logger.log_message(:user, msg, format_messages_for_log(context_view))

      # Execute LLM request
      response = @client.execute(context_view)

      if (req = response.raw_request) && (res = response.raw_response)
        @logger.log_api_payloads(req, res)
      end

      # Extract text content from Response (ignore tool_calls in base ChatFlow)
      response_text = response.content || ""

      @context_manager.handle_bot_message(response_text)
      updated_context = @context_manager.current_view(ephemeral_blocks)
      @logger.log_message(:bot, response_text, format_messages_for_log(updated_context), response.thinking)
      Mantle.emit_status(:idle)

      on_response.call(response)
    end
  end

  # Represents a chat flow with support for executing tools in a loop.
  #
  # Extends `ChatFlow` to handle tool calls until a final text response is received.
  class ToolEnabledChatFlow < ChatFlow
    # Represents the default maximum number of tool execution iterations per run.
    DEFAULT_MAX_ITERATIONS = 10

    # Represents the maximum nested execution depth for tools to prevent recursion.
    MAX_SUBAGENT_DEPTH = 1

    # :nodoc:
    @depth : Int32

    # Creates a tool-enabled chat flow with *context_manager*, *client*, *logger*, and optional *depth*.
    def initialize(
      context_manager : Mantle::Storage::ContextManager,
      client : Mantle::Clients::Client,
      logger : Mantle::Support::Logger,
      @depth : Int32 = 0,
    )
      super(context_manager, client, logger)
    end

    # Runs the tool-enabled chat flow, processing LLM requests and executing tool calls in a loop until a final text response is produced.
    #
    # Takes the initial user message *msg*, list of *builtins*, *custom_tools*, tool execution callback *tool_callback*,
    # safety *builtin_config*, maximum tool loop limit *max_iterations*, chunk callback *on_chunk*, and response callback *on_response*.
    def run(
      msg : String,
      builtins : Array(Mantle::Tools::BuiltinTool)? = nil,
      custom_tools : Array(Mantle::Tools::Tool)? = nil,
      tool_callback : Proc(String, Hash(String, JSON::Any), String)? = nil,
      builtin_config : Mantle::Tools::BuiltinToolConfig? = nil,
      max_iterations : Int32 = DEFAULT_MAX_ITERATIONS,
      on_chunk : Proc(String, Nil)? = nil,
      on_response : Proc(Mantle::Clients::Response, Nil)? = nil,
      ephemeral_blocks : Array(String) = [] of String,
      invisible_append : String? = nil,
    )
      # Add user message to context
      @context_manager.handle_user_message(msg, invisible_append)
      context_view = @context_manager.current_view(ephemeral_blocks)
      @logger.log_message(:user, msg, format_messages_for_log(context_view))

      # Merge tool definitions
      all_tools = merge_tools(builtins, custom_tools)

      # Extract tool names for error messages
      tool_names = all_tools ? all_tools.map { |t| t.function.name } : nil

      # Create tool executor
      tool_executor = Mantle::Tools::ToolExecutor.new(builtin_config, tool_callback, @context_manager.bot_name)

      # Tool call loop
      iteration = 0
      failed_calls = [] of {String, JSON::Any}
      loop do
        iteration += 1

        if iteration > max_iterations
          handle_tool_limit(max_iterations, ephemeral_blocks, on_chunk, on_response)
          break
        end

        # Execute LLM with tools
        response = execute_and_parse(context_view, all_tools, on_chunk)

        # Check if we have a text response (end of loop)
        if response.content && (response.tool_calls.nil? || response.tool_calls.not_nil!.empty?)
          handle_final_response(response, ephemeral_blocks, on_response)
          break
        end

        # We have tool calls - process them
        if tool_calls = response.tool_calls
          begin
            # Check for repeated failures before executing
            tool_calls.each do |call|
              begin
                parsed_args = JSON.parse(call.function.arguments)
                if failed_calls.includes?({call.function.name, parsed_args})
                  raise Mantle::Tools::TerminalToolError.new("Tool '#{call.function.name}' with arguments '#{call.function.arguments}' has already failed in this turn. Aborting tool loop to prevent infinite loop.")
                end
              rescue ex : Mantle::Tools::TerminalToolError
                raise ex
              rescue
                # Ignore JSON parse errors for arguments check, let execution handle it
              end
            end

            context_view = process_tools(tool_calls, tool_names, tool_executor, response, ephemeral_blocks, context_view, failed_calls)
          rescue ex : Mantle::Tools::TerminalToolError
            handle_terminal_error(ex.message || "Terminal tool failure", ephemeral_blocks, on_response)
            break
          end
        else
          # No content and no tool calls - shouldn't happen, but handle it
          handle_empty_response(response, ephemeral_blocks, on_response)
          break
        end
      end
    end

    private def handle_tool_limit(max_iterations : Int32, ephemeral_blocks : Array(String), on_chunk : Proc(String, Nil)?, on_response : Proc(Mantle::Clients::Response, Nil)?)
      error_msg = "System: Maximum number of tool iterations (#{max_iterations}) reached. Please provide a text response to the user now without using any more tools."
      @context_manager.add_message("system", error_msg, check_consolidation: false)

      # Force one last client call without tools to get the final text response
      final_context = @context_manager.current_view(ephemeral_blocks)
      final_response = if on_chunk
                         @client.execute(final_context, nil, &on_chunk)
                       else
                         @client.execute(final_context, nil)
                       end

      if (req = final_response.raw_request) && (res = final_response.raw_response)
        @logger.log_api_payloads(req, res)
      end

      # Handle the text response
      response_text = final_response.content || "Error: Failed to generate final response after hitting tool iteration limit."
      @context_manager.handle_bot_message(response_text, check_consolidation: false)

      # Check consolidation now that the full turn is complete
      @context_manager.check_and_consolidate

      updated_context = @context_manager.current_view(ephemeral_blocks)
      @logger.log_message(:bot, response_text, format_messages_for_log(updated_context), final_response.thinking)

      on_response.try(&.call(final_response))
    end

    private def execute_and_parse(context_view : Array(Hash(String, String)), all_tools : Array(Mantle::Tools::Tool)?, on_chunk : Proc(String, Nil)?) : Mantle::Clients::Response
      # If depth >= MAX_SUBAGENT_DEPTH, strip tools to prevent recursion
      tools_to_pass = (@depth >= MAX_SUBAGENT_DEPTH) ? nil : all_tools

      response = if on_chunk
                   @client.execute(context_view, tools_to_pass, &on_chunk)
                 else
                   @client.execute(context_view, tools_to_pass)
                 end

      if (req = response.raw_request) && (res = response.raw_response)
        @logger.log_api_payloads(req, res)
      end

      response
    end

    private def handle_final_response(response : Mantle::Clients::Response, ephemeral_blocks : Array(String), on_response : Proc(Mantle::Clients::Response, Nil)?)
      # Final text response - add to context without consolidation check
      response_text = response.content.not_nil!
      @context_manager.handle_bot_message(response_text, check_consolidation: false)

      # Check consolidation now that the full turn is complete
      @context_manager.check_and_consolidate

      updated_context = @context_manager.current_view(ephemeral_blocks)
      @logger.log_message(:bot, response_text, format_messages_for_log(updated_context), response.thinking)
      Mantle.emit_status(:idle)

      on_response.try(&.call(response))
    end

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

    private def handle_terminal_error(
      error_msg : String,
      ephemeral_blocks : Array(String),
      on_response : Proc(Mantle::Clients::Response, Nil)?,
    )
      response_text = "Error: #{error_msg}"
      @context_manager.handle_bot_message(response_text, check_consolidation: false)

      # Check consolidation now that the full turn is complete
      @context_manager.check_and_consolidate

      updated_context = @context_manager.current_view(ephemeral_blocks)
      @logger.log_message(:bot, response_text, format_messages_for_log(updated_context))
      Mantle.emit_status(:idle)

      synthetic_response = Mantle::Clients::Response.new(content: response_text, tool_calls: nil)
      on_response.try(&.call(synthetic_response))
    end

    private def process_tools(
      tool_calls : Array(Mantle::Clients::ToolCall),
      tool_names : Array(String)?,
      tool_executor : Mantle::Tools::ToolExecutor,
      response : Mantle::Clients::Response,
      ephemeral_blocks : Array(String),
      context_view : Array(Hash(String, String)),
      failed_calls : Array({String, JSON::Any}),
    ) : Array(Hash(String, String))
      Mantle.emit_status(:tool_loop)
      # Log detailed tool call information (natural language)
      tool_calls.each do |call|
        formatted_call = Mantle::Tools::ToolFormatter.format_tool_call(call)
        @logger.log_message(:bot, formatted_call, format_messages_for_log(context_view), response.thinking)
      end

      # Add assistant message to context if there's content (defer consolidation)
      if response.content && !response.content.not_nil!.empty?
        @context_manager.handle_bot_message(response.content.not_nil!, check_consolidation: false)
      end

      # Execute tools
      tool_results = tool_executor.execute_all(tool_calls, tool_names)

      # Add tool results to context with 'tool' role (defer consolidation)
      tool_results.each_with_index do |result, idx|
        content_with_id = "Result from #{result.tool_call_id}: #{result.result}"
        @context_manager.add_message("tool", content_with_id, check_consolidation: false)

        # Log detailed tool result (natural language)
        formatted_result = Mantle::Tools::ToolFormatter.format_tool_result(result)
        @logger.log_message(:bot, formatted_result, format_messages_for_log(@context_manager.current_view(ephemeral_blocks)))

        # Track failed calls
        if failed_result?(result.result)
          call = tool_calls[idx]
          begin
            parsed_args = JSON.parse(call.function.arguments)
            failed_calls << {call.function.name, parsed_args}
          rescue
            # Ignore argument parsing error
          end
        end
      end

      # Update context view for next iteration
      @context_manager.current_view(ephemeral_blocks)
    end

    private def handle_empty_response(response : Mantle::Clients::Response, ephemeral_blocks : Array(String), on_response : Proc(Mantle::Clients::Response, Nil)?)
      response_text = ""
      @context_manager.handle_bot_message(response_text, check_consolidation: false)

      # Check consolidation now that the turn is complete
      @context_manager.check_and_consolidate
      Mantle.emit_status(:idle)

      on_response.try(&.call(response))
    end

    # Merge built-in and custom tool definitions
    private def merge_tools(builtins : Array(Mantle::Tools::BuiltinTool)?, custom : Array(Mantle::Tools::Tool)?) : Array(Mantle::Tools::Tool)?
      tools = [] of Mantle::Tools::Tool

      # Add built-in tool definitions
      if builtins && !builtins.empty?
        tools.concat(Mantle::Tools::BuiltinToolRegistry.definitions_for(builtins))
      end

      # Add custom tools
      if custom && !custom.empty?
        tools.concat(custom)
      end

      tools.empty? ? nil : tools
    end
  end
end
