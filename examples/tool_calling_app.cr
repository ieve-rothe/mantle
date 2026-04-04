#!/usr/bin/env crystal

# Tool Calling Example Application
# Demonstrates Mantle's tool calling capabilities with both built-in and custom tools

require "../src/mantle"

# Define a custom tool for getting the current time
def create_time_tool
  Mantle::Tool.new(
    function: Mantle::FunctionDefinition.new(
      name: "get_current_time",
      description: "Get the current time in a specific timezone",
      parameters: Mantle::ParametersSchema.new(
        properties: {
          "timezone" => Mantle::PropertyDefinition.new(
            type: "string",
            description: "Timezone (e.g., 'UTC', 'America/New_York')"
          )
        },
        required: ["timezone"]
      )
    )
  )
end

# Custom tool callback implementation
def custom_tool_handler(name : String, args : Hash(String, JSON::Any)) : String
  case name
  when "get_current_time"
    timezone = args["timezone"]?.try(&.as_s) || "UTC"

    # Simple timezone handling (in production, use proper timezone library)
    time = case timezone
           when "UTC"
             Time.utc.to_s("%H:%M:%S")
           when "America/New_York"
             (Time.utc - 5.hours).to_s("%H:%M:%S") + " EST"
           else
             Time.utc.to_s("%H:%M:%S") + " UTC"
           end

    %({"success":true,"time":"#{time}","timezone":"#{timezone}"})
  else
    %({"error":"Unknown custom tool: #{name}"})
  end
end

# Main application
puts "=" * 60
puts "Mantle Tool Calling Example"
puts "=" * 60
puts

# Setup Mantle components
model_config = Mantle::ModelConfig.new(
  "llama3.2:latest",   # model_name
  false,                # stream
  0.7,                  # temperature
  0.9,                  # top_p
  500,                  # max_tokens
  "http://localhost:11434/api/chat" # Ollama API URL
)

client = Mantle::LlamaClient.new(model_config)

# Use ephemeral sliding window context (keeps last 50 messages)
context_store = Mantle::EphemeralSlidingContextStore.new(
  "You are a helpful assistant with access to tools. Use tools when appropriate.",
  50 # messages_to_keep
)

# Memory store (not actively used in this short example)
memory_store = Mantle::JSONLayeredMemoryStore.new(
  memory_file: "/tmp/tool_example_memory.json",
  layer_capacity: 10,
  layer_target: 5,
  squishifier: ->(messages : Array(String)) : String { messages.join(" | ") }
)

context_manager = Mantle::ContextManager.new(
  context_store,
  memory_store,
  "User",
  "Assistant"
)

logger = Mantle::FileLogger.new("/tmp/tool_example.log", "User", "Assistant")

# Create ToolEnabledChatFlow
flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

# Configure built-in tool access
builtin_config = Mantle::BuiltinToolConfig.new(
  working_directory: Dir.current,
  allowed_paths: [Dir.current, "/tmp"]
)

# Define which tools are available
builtins = [
  Mantle::BuiltinTool::ReadFile,
  Mantle::BuiltinTool::ListDirectory
]

custom_tools = [
  create_time_tool
]

# Example conversation demonstrating tool usage
puts "Example 1: Using built-in list_directory tool"
puts "-" * 60

flow.run(
  "List the files in the current directory.",
  builtins: builtins,
  builtin_config: builtin_config,
  on_response: ->(response : String) {
    puts "Assistant: #{response}"
    puts
  }
)

puts "Example 2: Using custom get_current_time tool"
puts "-" * 60

flow.run(
  "What time is it in UTC?",
  custom_tools: custom_tools,
  tool_callback: ->custom_tool_handler(String, Hash(String, JSON::Any)),
  on_response: ->(response : String) {
    puts "Assistant: #{response}"
    puts
  }
)

puts "Example 3: Using built-in read_file tool"
puts "-" * 60

# Create a test file to read
test_file = File.join(Dir.current, "README.md")

if File.exists?(test_file)
  flow.run(
    "Read the first few lines of README.md",
    builtins: builtins,
    builtin_config: builtin_config,
    on_response: ->(response : String) {
      puts "Assistant: #{response}"
      puts
    }
  )
else
  puts "README.md not found, skipping this example"
  puts
end

puts "Example 4: Combining built-in and custom tools"
puts "-" * 60

flow.run(
  "List the files in the current directory and tell me what time it is in UTC.",
  builtins: builtins,
  custom_tools: custom_tools,
  builtin_config: builtin_config,
  tool_callback: ->custom_tool_handler(String, Hash(String, JSON::Any)),
  on_response: ->(response : String) {
    puts "Assistant: #{response}"
    puts
  }
)

puts "=" * 60
puts "Tool calling examples complete!"
puts "Check /tmp/tool_example.log for detailed logs"
puts "=" * 60
