# examples/03_tool_calling.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Level 3: Tool Calling with Step
#
# This example demonstrates Step executing tools in a bounded loop.
# When the model requests tool calls, Step runs the tools and feeds
# results back into the inference loop until a final text response is produced.

require "../src/mantle"

puts "--- Level 3: Tool Calling ---"

# 1. Setup Client and Context
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

context_manager = Mantle::Storage::ContextManager.new(
  context_store: Mantle::Storage::JSONContextStore.new(
    system_prompt: "You are a helpful assistant with access to tools. Always use tools to verify information before answering.",
    context_file: "examples/03_context.json"
  ),
  memory_store: Mantle::Storage::JSONLayeredMemoryStore.new(
    memory_file: "examples/03_memory.json",
    layer_token_capacity: 100,
    layer_token_target: 50,
    squishifier: Mantle::Support::Squishifiers.build_basic_summarizer(client)
  ),
  user_name: "User",
  bot_name: "Assistant",
  token_target: 600,
  token_hardmax: 1200
)

# 2. Define Tools with executable blocks
random_tool = Mantle::Tools::Tool.new(
  function: Mantle::Tools::FunctionDefinition.new(
    name: "get_random_number",
    description: "Gets a random number between a min and max value.",
    parameters: Mantle::Tools::ParametersSchema.new(
      properties: {
        "min" => Mantle::Tools::PropertyDefinition.new(type: "integer", description: "The minimum value"),
        "max" => Mantle::Tools::PropertyDefinition.new(type: "integer", description: "The maximum value"),
      },
      required: ["min", "max"]
    )
  )
) do |args|
  min = args["min"]?.try(&.as_i?) || 1
  max = args["max"]?.try(&.as_i?) || 100
  random_num = rand(min..max)
  %({"success": true, "number": #{random_num}})
end

# 3. Build the Step
step = Mantle::Step.new(
  client: client,
  tools: [random_tool],
  max_iterations: 10,
  on_status: ->(flag : Symbol) { puts "Status update: #{flag}" }
)

# 4. Run the Step
context_manager.handle_user_message("Pick a random number between 1 and 100, then tell me if it is even or odd.")
result = step.run(context_manager.current_view)

if result.ok?
  reply = result.unwrap
  context_manager.handle_bot_message(reply)
  puts "\nFinal Answer: #{reply}"
  puts "Iterations taken: #{result.iterations}"
else
  puts "Step failed with error: #{result.error}"
end

puts "--- Finished ---"
