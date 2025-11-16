# examples/basic_app.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Basic example / test harness application
# (Stub)

require "../src/mantle.cr"

# Using same dummy context store as unit tests. Only thing we use it for so far is the system prompt.
class DummyContextStore < Mantle::ContextStore
  property system_prompt : String = "This is a test system prompt"

  def scratchpad : Hash(String, JSON::Any)
    Hash(String, JSON::Any).new
  end
end

workspace = DummyContextStore.new
logger = Mantle::FileLogger.new("basic_app_log.txt")
model_config = Mantle::ModelConfig.new(
    "gpt-oss:20b",                        # model_name
    false,                                # stream
    0.6,                                  # temperature
    0.7,                                  # top_p
    700,                                  # max_tokens
    "http://localhost:11434/api/generate" # api_url
  )
client = Mantle::LlamaClient.new(model_config)
flow = Mantle::Flow.new(workspace,
                client,
                model_config,
                logger,
                "basic_app_log.txt")

flow.run("Hi")