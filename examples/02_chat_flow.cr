# examples/02_chat_flow.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Level 2: Chat Flow
#
# This example builds on the basic client by introducing Mantle's core abstractions:
# - ContextStore: To track the sliding window of conversation.
# - MemoryStore: To summarize older messages when the context window fills up.
# - ContextManager: To coordinate moving messages between the two stores.
# - ChatFlow: A pre-built loop that handles passing user messages, calling the model, and updating context.

require "../src/mantle"

puts "--- Level 2: Chat Flow ---"

# 1. Setup the Client
client = Mantle::LlamaClient.new(
  Mantle::ModelConfig.new(
    model_name: "gpt-oss:20b",
    stream: false,
    temperature: 0.7,
    top_p: 0.85,
    max_tokens: 1000,
    api_url: "http://localhost:11434/api/chat"
  )
)

# 2. Setup the Context Store
# We use JSONContextStore to automatically save our conversation to a file.
context_store = Mantle::JSONContextStore.new(
  system_prompt: "You are a helpful assistant.",
  context_file: "examples/02_context.json"
)

# 3. Setup the Memory Store
# We use JSONLayeredMemoryStore to save long-term summaries to a file.
memory_store = Mantle::JSONLayeredMemoryStore.new(
  memory_file: "examples/02_memory.json",
  layer_capacity: 10,
  layer_target: 5,
  # We use a built-in squishifier that uses our client to summarize old messages.
  squishifier: Mantle::Squishifiers.build_basic_summarizer(client)
)

# 4. Setup the Context Manager
# The ContextManager ties the ContextStore and MemoryStore together.
# - msg_hardmax: When the context reaches this many messages, it triggers consolidation.
# - msg_target: After consolidation, this many recent messages are kept in context.
context_manager = Mantle::ContextManager.new(
  context_store: context_store,
  memory_store: memory_store,
  user_name: "User",
  bot_name: "Assistant",
  msg_target: 4,
  msg_hardmax: 8
)

# 5. Setup Logging
# FileLogger writes formatted chat logs to a file.
logger = Mantle::FileLogger.new("examples/02_chat.log", "User", "Assistant")

# 6. Build the Flow
# ChatFlow orchestrates the whole process.
flow = Mantle::ChatFlow.new(
  context_manager: context_manager,
  client: client,
  logger: logger
)

# 7. Run the Flow
# Instead of managing raw message arrays manually, we just call #run.
flow.run(
  msg: "Hello! What can you do?",
  on_response: ->(resp : Mantle::Response) {
    puts "Assistant: #{resp.content}"
  }
)

puts "\nCheck examples/02_context.json and examples/02_chat.log for the persisted data!"
puts "--- Finished ---"
