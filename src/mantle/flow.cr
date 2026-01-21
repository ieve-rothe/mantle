# mantle/flow.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Represents a generic LLM inference operation
#
# Base class for different LLM-based processing flows.
# Examples include planning steps, command generation, reflection, etc.

require "./context_store.cr"
require "./client.cr"
require "./logger.cr"

module Mantle
  # Represents a generic LLM inference operation
  #
  # Base class for different LLM-based processing flows.
  # Examples include flows for planning steps, command generation, reflection, etc.
  class Flow
    property context_store : ContextStore
    property client : Client
    property logger : Logger

    # Custom errors for flow operations
    class InputError < Exception; end

    def initialize(
      @context_store : ContextStore,
      @client : Client,
      @logger : Logger,
    )
    end

    # Assemble context, send it to client, set model response in class
    def run(input : String, on_response : Proc(String,Nil))
      # To be implemented by specific flows
    end
  end

  class ChatFlow < Flow
    property user_name : String = "User"
    property bot_name : String = "Assistant"

    def run(input : String, on_response : Proc(String,Nil))
      @context_store.add_message(user_name, input)
      @logger.log_user_message(input)
      @logger.log_context(@context_store.chat_context)
      response = @client.execute(@context_store.chat_context)
      @context_store.add_message(bot_name, response)
      @logger.log_bot_message(response)
      on_response.call(response)
    end
  end
end
