#!/usr/bin/env crystal

# Tool Calling Example Application
# Demonstrates Mantle's tool calling capabilities with both built-in and custom tools
# This version uses JSON-backed context store and tests memory consolidation

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

# Clean up any previous test files
context_file = "/tmp/tool_example_context.json"
memory_file = "/tmp/tool_example_memory.json"
log_file = "/tmp/tool_example.log"

File.delete(context_file) if File.exists?(context_file)
File.delete(memory_file) if File.exists?(memory_file)
File.delete(log_file) if File.exists?(log_file)

# Main application
puts "=" * 70
puts "Mantle Tool Calling + Memory Consolidation Example"
puts "=" * 70
puts "This example demonstrates:"
puts "  - Tool calling with both built-in and custom tools"
puts "  - JSON-backed context persistence"
puts "  - Memory consolidation when context limit is reached"
puts "=" * 70
puts

# Setup Mantle components
model_config = Mantle::ModelConfig.new(
  "gemma4:e2b",                    # model_name
  false,                            # stream
  0.7,                              # temperature
  0.9,                              # top_p
  500,                              # max_tokens
  "http://localhost:11434/api/chat" # Ollama API URL
)

client = Mantle::LlamaClient.new(model_config)

# Use JSON-backed context store for persistence
context_store = Mantle::JSONContextStore.new(
  "You are a helpful assistant with access to tools. Use tools when appropriate to answer user questions.",
  context_file
)

# Memory store with proper squishifier that uses the model
summarizer_prompt = "You are an internal memory consolidation system for an AI assistant. Review the following conversation history and tool interactions. Synthesize them into a concise 2-3 sentence summary. Focus on key facts, tool results, and actionable information. Ignore casual conversation. Write from the assistant's perspective."
squishifier = Mantle::Squishifiers.build_basic_summarizer(client, summarizer_prompt)

memory_store = Mantle::JSONLayeredMemoryStore.new(
  memory_file: memory_file,
  layer_capacity: 10,
  layer_target: 5,
  squishifier: squishifier
)

# Context manager with LOW msg_hardmax to trigger consolidation quickly
context_manager = Mantle::ContextManager.new(
  context_store,
  memory_store,
  "User",
  "Assistant",
  msg_target: 4,    # Keep 4 messages after consolidation
  msg_hardmax: 8    # Trigger consolidation at 8 messages (low limit for testing)
)

logger = Mantle::FileLogger.new(log_file, "User", "Assistant")

# Create ToolEnabledChatFlow
flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

# Configure built-in tool access
builtin_config = Mantle::BuiltinToolConfig.new(
  working_directory: Dir.current,
  allowed_paths: [Dir.current, "/tmp"],
  notify_icon: File.expand_path("../assets/icon.png", __DIR__),
  autonomous_zone_paths: [File.join(Dir.current, "examples", "sandbox")],
  file_backup_count: 3
)

# Define which tools are available
builtins = [
  Mantle::BuiltinTool::ReadFile,
  Mantle::BuiltinTool::ListDirectory,
  Mantle::BuiltinTool::NotifySend,
  Mantle::BuiltinTool::WriteFile
]

custom_tools = [
  create_time_tool
]

# Callback for displaying responses
display_response = ->(response : String) {
  puts "Assistant: #{response}"
  puts
  puts "[Context messages: #{context_store.current_num_messages}/#{context_manager.msg_hardmax}]"
  puts
}

# Extended conversation to trigger memory consolidation
puts "Starting conversation with multiple interactions..."
puts "=" * 70
puts

puts "[Turn 1] Basic greeting"
puts "-" * 70
flow.run(
  "Hello! I need help exploring this project.",
  on_response: display_response
)

puts "[Turn 2] Using list_directory tool"
puts "-" * 70
flow.run(
  "Can you list the files in the current directory?",
  builtins: builtins,
  builtin_config: builtin_config,
  on_response: display_response
)

puts "[Turn 3] Using get_current_time tool"
puts "-" * 70
flow.run(
  "What time is it in UTC?",
  custom_tools: custom_tools,
  tool_callback: ->custom_tool_handler(String, Hash(String, JSON::Any)),
  on_response: display_response
)

puts "[Turn 4] Asking about the project"
puts "-" * 70
flow.run(
  "What kind of project is this based on the files you saw?",
  on_response: display_response
)

puts "[Turn 5] Using read_file tool"
puts "-" * 70
if File.exists?(File.join(Dir.current, "README.md"))
  flow.run(
    "Can you read the README.md file and tell me what this project does?",
    builtins: builtins,
    builtin_config: builtin_config,
    on_response: display_response
  )
else
  flow.run(
    "Tell me more about the Mantle framework.",
    on_response: display_response
  )
end

puts "[Turn 6] Follow-up question"
puts "-" * 70
flow.run(
  "That's interesting! What are the main components of this framework?",
  on_response: display_response
)

puts "[Turn 7] Combining multiple tools"
puts "-" * 70
flow.run(
  "Check the time again and also list any .cr files in the examples directory.",
  builtins: builtins,
  custom_tools: custom_tools,
  builtin_config: builtin_config,
  tool_callback: ->custom_tool_handler(String, Hash(String, JSON::Any)),
  on_response: display_response
)

puts "[Turn 8] Final question about consolidation"
puts "-" * 70
flow.run(
  "Can you summarize what we've discussed so far?",
  on_response: display_response
)

puts "[Turn 9] Notify Send Example"
puts "-" * 70
flow.run(
  "Send me a desktop notification telling me the summary is complete.",
  builtins: builtins,
  builtin_config: builtin_config,
  on_response: display_response
)

puts "[Turn 10] Write File Example"
puts "-" * 70
flow.run(
  "Please write a small text file saying 'Hello from Mantle tools!' in the examples/sandbox folder.",
  builtins: builtins,
  builtin_config: builtin_config,
  on_response: display_response
)

puts "=" * 70
puts "Conversation complete!"
puts
puts "Files created:"
puts "  - Context: #{context_file}"
puts "  - Memory: #{memory_file}"
puts "  - Logs: #{log_file}"
puts
puts "Note: Memory consolidation should have been triggered during this conversation"
puts "      due to the low msg_hardmax (8 messages) setting."
puts "=" * 70
