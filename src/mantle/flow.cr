# mantle/flow.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Represents a generic LLM inference operation
#
# Base class for different LLM-based processing flows.
# Examples include planning steps, command generation, reflection, etc.


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

      @context_manager.handle_bot_message(response)
      updated_context = @context_manager.current_view
      @logger.log_message(:bot, response, format_messages_for_log(updated_context))

      on_response.call(response)
    end
  end
end
