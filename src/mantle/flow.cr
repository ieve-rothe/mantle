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
    property workspace : ContextStore
    property client : Client
    property model_config : ModelConfig
    property logger : Logger
    property output_file : String

    property context : String?
    property output : String?

    # Custom errors for flow operations
    class InputError < Exception; end

    def initialize(
      @workspace : ContextStore,
      @client : Client,
      @model_config : ModelConfig,
      @logger : Logger,
      @output_file : String,
    )
    end

    # Assemble context, send it to client, set model response in class
    def run(input : String)
      @context = build_context(input)
      @logger.log("Context Input", @context.not_nil!)
      @output = @client.execute(@context.not_nil!)
      @logger.log("Model Response", @output.not_nil!)
    end

    # ---------

    # Base class just uses system prompt and input as context.
    private def build_context(input : String) : String
      context = @workspace.system_prompt + "\n" + input
    end
  end
end
