# examples/tool_calling_app.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../src/mantle"

puts "--- Tool Calling App with Step ---"

context_file = "/tmp/tool_example_context.json"
memory_file = "/tmp/tool_example_memory.json"
File.delete(context_file) if File.exists?(context_file)
File.delete(memory_file) if File.exists?(memory_file)

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

context_store = Mantle::Storage::JSONContextStore.new(
  "You are a helpful assistant with access to tools. Use tools when appropriate to answer user questions.",
  context_file
)

summarizer_prompt = "You are an internal memory consolidation system for an AI assistant. Review the following conversation history and tool interactions. Synthesize them into a concise 2-3 sentence summary."
squishifier = Mantle::Support::Squishifiers.build_basic_summarizer(client, summarizer_prompt)

memory_store = Mantle::Storage::JSONLayeredMemoryStore.new(
  memory_file: memory_file,
  layer_token_capacity: 10,
  layer_token_target: 5,
  squishifier: squishifier
)

context_manager = Mantle::Storage::ContextManager.new(
  context_store,
  memory_store,
  "User",
  "Assistant",
  token_target: 4,
  token_hardmax: 8
)

time_tool = Mantle::Tools::Tool.new(
  function: Mantle::Tools::FunctionDefinition.new(
    name: "get_current_time",
    description: "Get the current time in UTC",
    parameters: Mantle::Tools::ParametersSchema.new(
      properties: {
        "timezone" => Mantle::Tools::PropertyDefinition.new(
          type: "string",
          description: "Timezone (e.g. UTC)"
        ),
      }
    )
  )
) do |args|
  Time.utc.to_s("%H:%M:%S UTC")
end

step = Mantle::Step.new(
  client: client,
  tools: [time_tool],
  max_iterations: 10,
  on_status: ->(flag : Symbol) { puts "Status: #{flag}" }
)

puts "Executing Turn 1..."
context_manager.handle_user_message("What time is it right now?")
result = step.run(context_manager.project_view)

# If result.value is not nil, it is assigned to `reply` and the block executes.
# If it is nil, it falls through to the else block.
if reply = result.value
  context_manager.handle_bot_message(reply)
  puts "Bot: #{reply}"
  puts "Iterations: #{result.iterations}"
else
  puts "Step error: #{result.error}"
end

context_manager.check_and_consolidate
puts "Done!"
