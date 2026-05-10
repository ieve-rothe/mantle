# examples/03_tool_calling.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Level 3: Tool Calling
#
# This example builds on Level 2 by introducing ToolEnabledChatFlow.
# This flow type handles complex model interactions where the model can request
# to run tools (like reading files, checking the weather, etc.) before giving
# a final text response.

require "../src/mantle"

puts "--- Level 3: Tool Calling ---"

# 1. Setup Client, Context, and Memory (same as Level 2)
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

context_manager = Mantle::ContextManager.new(
  context_store: Mantle::JSONContextStore.new(
    system_prompt: "You are a helpful assistant with access to tools. Always use tools to verify information before answering.",
    context_file: "examples/03_context.json"
  ),
  memory_store: Mantle::JSONLayeredMemoryStore.new(
    memory_file: "examples/03_memory.json",
    layer_capacity: 10,
    layer_target: 5,
    squishifier: Mantle::Squishifiers.build_basic_summarizer(client)
  ),
  user_name: "User",
  bot_name: "Assistant",
  msg_target: 6,
  msg_hardmax: 12
)

logger = Mantle::FileLogger.new("examples/03_chat.log", "User", "Assistant")

# 2. Build the Tool Enabled Flow
# ToolEnabledChatFlow has built-in logic to parse tool requests from the model,
# execute them, and feed the results back into the model until a text response is ready.
flow = Mantle::ToolEnabledChatFlow.new(
  context_manager: context_manager,
  client: client,
  logger: logger
)

# 3. Configure Built-in Tools
# Mantle provides a set of secure built-in tools (like ReadFile, ListDirectory).
# You must configure security boundaries to prevent the AI from accessing sensitive files.
builtin_config = Mantle::BuiltinToolConfig.new(
  working_directory: Dir.current,
  allowed_paths: [Dir.current],                                           # Only allow reading within this repo
  autonomous_zone_paths: [File.join(Dir.current, "examples", "sandbox")], # Allow writing only in the sandbox folder
  file_backup_count: 3
)

# Specify which built-in tools we want to give the model access to
builtins = [
  Mantle::BuiltinTool::ReadFile,
  Mantle::BuiltinTool::ListDirectory,
]

# 4. Define a Custom Tool
# You can define your own tools! A Tool needs a FunctionDefinition (schema).
def create_random_number_tool
  Mantle::Tool.new(
    function: Mantle::FunctionDefinition.new(
      name: "get_random_number",
      description: "Gets a random number between a min and max value.",
      parameters: Mantle::ParametersSchema.new(
        properties: {
          "min" => Mantle::PropertyDefinition.new(type: "integer", description: "The minimum value"),
          "max" => Mantle::PropertyDefinition.new(type: "integer", description: "The maximum value"),
        },
        required: ["min", "max"]
      )
    )
  )
end

# You also need a handler method to execute the logic when the model calls your custom tool.
def custom_tool_handler(name : String, args : Hash(String, JSON::Any)) : String
  case name
  when "get_random_number"
    min = args["min"]?.try(&.as_i?) || 1
    max = args["max"]?.try(&.as_i?) || 100
    random_num = rand(min..max)
    %({"success": true, "number": #{random_num}})
  else
    %({"error": "Unknown custom tool"})
  end
end

custom_tools = [create_random_number_tool]

# 5. Run the Flow with Tools
puts "User: Pick a random number between 1 and 10, then read the README.md file and tell me what the project is called."

flow.run(
  msg: "Pick a random number between 1 and 10, then read the README.md file and tell me what the project is called.",
  builtins: builtins,
  builtin_config: builtin_config,
  custom_tools: custom_tools,
  tool_callback: ->custom_tool_handler(String, Hash(String, JSON::Any)),
  on_response: ->(resp : Mantle::Response) {
    # If the model emits reasoning blocks, we can see them.
    if thinking = resp.thinking
      puts "\n🤔 Thinking:\n#{thinking}"
    end
    puts "\nAssistant: #{resp.content}"
  }
)

puts "\n--- Finished ---"
