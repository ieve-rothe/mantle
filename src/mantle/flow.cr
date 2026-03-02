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
  end

  class ChatFlow < Flow
    def run(msg : String, on_response : Proc(String, Nil))
      @context_manager.handle_user_message(msg)
      @logger.log_message(:user, msg, @context_manager.current_view)

      response = @client.execute(@context_manager.current_view)

      @context_manager.handle_bot_message(response)
      @logger.log_message(:bot, response, @context_manager.current_view)

      on_response.call(response)
    end
  end
end
