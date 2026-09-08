# examples/04_session.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Level 4: Session Pipeline, Mixed Provenance & Ephemeral Injections
#
# This example demonstrates Mantle's high-level Session orchestrator:
# - Mixed message provenance via << operator (String defaults to "user", Mantle::Message preserves role)
# - Spatial Ephemeral Injections (system, pre-history, and tail injections)
# - Idempotent turn retries (prevents duplicate trigger messages in context)
# - Structured audit receipts emitted to JSONL

require "../src/mantle"

puts "--- Level 4: Session Pipeline & Injections ---"

# 1. Setup Model Client
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

# 2. Setup Context & Memory Stores
context_store = Mantle::Storage::JSONContextStore.new(
  system_prompt: "You are an autonomous assistant operating under the Mantle framework.",
  context_file: "examples/04_context.json"
)

memory_store = Mantle::Storage::JSONLayeredMemoryStore.new(
  memory_file: "examples/04_memory.json",
  layer_token_capacity: 100,
  layer_token_target: 50,
  squishifier: Mantle::Support::Squishifiers.build_basic_summarizer(client)
)

# 3. Setup Context Manager
context_manager = Mantle::Storage::ContextManager.new(
  context_store: context_store,
  memory_store: memory_store,
  user_name: "Cam",
  bot_name: "MantleAssistant",
  token_target: 500,
  token_hardmax: 1000
)

# 4. Build Step and Session
step = Mantle::Step.new(client: client)
session = Mantle::Session.new(
  context_manager: context_manager,
  step: step,
  log_file: "examples/04_receipts.jsonl",
  model_name: "gpt-oss:20b"
)

# 5. Mixed Provenance via `<<` Operator
puts "\n[1] Appending mixed provenance events to Session context graph:"
# A plain String defaults to role: "user"
session << "Morning sync started. Reviewing system alerts."
puts "  -> Appended user message via session << String"

# A Mantle::Message preserves explicit roles, e.g. system interrupts from daemons or cron
session << Mantle::Message.new("system", "[DAEMON_EVENT] Background file watcher detected changes in src/")
puts "  -> Appended system event via session << Mantle::Message"

# 6. Execute Turn with Spatial Ephemeral Injections
puts "\n[2] Executing turn with Spatial Ephemeral Injections:"
result = session.run_turn(
  trigger: "Provide a quick 1-sentence health status.",
  system_injections: ["CRITICAL: Operational Mode is SANDBOX_SIMULATION."],
  pre_history_injections: ["Workspace path: /home/cam/repos/adjutant"],
  tail_injections: ["Format output as: [STATUS: <ok|warn|err>] <summary>"]
)

if reply = result.value
  puts "Assistant: #{reply}"
else
  puts "Step failed with error: #{result.error}"
end

# 7. Demonstrate Retry Idempotency
puts "\n[3] Demonstrating Retry Idempotency contract:"
puts "Triggering retry with is_retry: true (e.g. after transient rate limit)..."
initial_count = context_store.current_view.size

retry_result = session.run_turn(
  trigger: "Provide a quick 1-sentence health status.",
  is_retry: true,
  tail_injections: ["Be even more concise."]
)

final_count = context_store.current_view.size
puts "Context message count before retry: #{initial_count}, after retry: #{final_count}"
puts "Trigger was not duplicated in canonical context graph: #{final_count == initial_count + 1}"

puts "\nAudit receipts logged to: examples/04_receipts.jsonl"
puts "--- Finished ---"
