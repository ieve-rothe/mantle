# examples/02_chat_flow.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Level 2: Step & Context Pipeline
#
# This example demonstrates Mantle's core decoupled abstractions:
# - ContextStore: Tracks conversation messages.
# - MemoryStore: Summarizes older messages when context fills up.
# - ContextManager: Coordinates context view and consolidation.
# - Step: Executes inference turns and returns strongly typed StepResult(T, E).

require "../src/mantle"

puts "--- Level 2: Step & Context Pipeline ---"

# 1. Setup the Client
client = Mantle::Clients::OllamaClient.new(
  Mantle::Clients::ModelConfig.new(
    model_name: "gpt-oss:20b",
    stream: false,
    temperature: 0.7,
    top_p: 0.85,
    max_tokens: 1000,
    api_url: "http://localhost:11434/api/chat"
  )
)

# 2. Setup Context and Memory Stores
context_store = Mantle::Storage::JSONContextStore.new(
  system_prompt: "You are a helpful assistant.",
  context_file: "examples/02_context.json"
)

memory_store = Mantle::Storage::JSONLayeredMemoryStore.new(
  memory_file: "examples/02_memory.json",
  layer_token_capacity: 100,
  layer_token_target: 50,
  squishifier: Mantle::Support::Squishifiers.build_basic_summarizer(client)
)

# 3. Setup Context Manager
context_manager = Mantle::Storage::ContextManager.new(
  context_store: context_store,
  memory_store: memory_store,
  user_name: "User",
  bot_name: "Assistant",
  token_target: 400,
  token_hardmax: 800
)

# 4. Build the Step Pipeline
step = Mantle::Step.new(client: client)

# 5. Run the Step
context_manager.handle_user_message("Hello! What can you do?")
result = step.run(context_manager.current_view)

# If result.value is not nil, it is assigned to `reply` and the block executes.
# If it is nil, it falls through to the else block.
if reply = result.value
  context_manager.handle_bot_message(reply)
  puts "Assistant: #{reply}"
else
  puts "Error during inference: #{result.error}"
end

puts "\nCheck examples/02_context.json for the persisted data!"
puts "--- Finished ---"
