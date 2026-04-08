require "../src/mantle.cr"

# Basic example showing implementation of a ChatFlow using a JSONSlidingContextStore, LayeredMemoryStore coordinated with a ContextManager

# 1. Setup Primitives
CONTEXT_FILE = "examples/test_context.json"
MEMORY_FILE = "examples/test_memory.json"
LOG_FILE     = "examples/test_log.txt"

# Clean up previous test files
[CONTEXT_FILE, MEMORY_FILE, LOG_FILE].each do |file|
  File.delete(file) if File.exists?(file)
end

# 2. Configure Logging
# The consumer application configures the `mantle` logger source
APP_LOG_FILE = "examples/test_app_log.txt"
File.delete(APP_LOG_FILE) if File.exists?(APP_LOG_FILE)

::Log.setup do |c|
  # We want a timestamped format for our application log
  formatter = ::Log::Formatter.new do |entry, io|
    io << entry.timestamp.to_utc.to_s("%Y-%m-%d %H:%M:%S")
    io << " [" << entry.severity.label << "] "
    io << entry.source << ": "
    io << entry.message
  end

  # Setup an IO backend writing to the app log file
  backend = ::Log::IOBackend.new(io: File.new(APP_LOG_FILE, "a"), formatter: formatter)

  # Bind the mantle logger to info level using our file backend
  c.bind("mantle", :info, backend)

  # Also print warnings and errors to stdout so the user sees them
  stdout_backend = ::Log::IOBackend.new(io: STDOUT)
  c.bind("mantle", :warn, stdout_backend)
end

# 3. Initialize Components
model_config = Mantle::ModelConfig.new(
  model_name: "gpt-oss:20b",
  stream: false,
  temperature: 1.0,
  top_p: 0.85,
  max_tokens: 5000,
  api_url: "http://localhost:11434/api/chat"
)

user_name = "Username"
bot_name = "Botname"

client = Mantle::LlamaClient.new(model_config)
logger = Mantle::FileLogger.new(LOG_FILE, user_name, bot_name, include_thinking: true)
context_store = Mantle::JSONContextStore.new(
  system_prompt: "Respond to the test.",
  context_file: CONTEXT_FILE
)
squishy = Mantle::Squishifiers.build_basic_summarizer(client)
memory_store = Mantle::JSONLayeredMemoryStore.new(
  memory_file: MEMORY_FILE,
  layer_capacity: 10,
  layer_target: 5,
  squishifier: squishy
)

context_manager = Mantle::ContextManager.new(
  context_store: context_store,
  memory_store: memory_store,
  user_name: user_name,
  bot_name: bot_name,
  msg_target: 6,
  msg_hardmax: 12,
  strip_thinking_tags: true  # Strip <think></think> blocks from model responses
)

# 4. Build the Flow
flow = Mantle::ChatFlow.new(
  context_manager: context_manager,
  client: client,
  logger: logger
)

# 5. Execute a single turn
puts "--- Starting Test Turn ---"

# Print status flags if any occurred during setup (e.g., :new_context_file)
if Mantle::Status.has?(:new_context_file)
  puts "NOTICE: A fresh context file was created."
  Mantle::Status.remove(:new_context_file)
end
input_text = "Hello! Are you running correctly?"

flow.run(
  msg: input_text,
  on_response: ->(resp : Mantle::Response) {
    puts "User: #{input_text}"
    if thinking = resp.thinking
      puts "\e[2m🤔 [Thinking]\n#{thinking}\n[Response]\e[0m"
    end
    puts "Bot: #{resp.content}"
  }
)

# 6. Verify the Context was updated
puts "\n--- Final Context State ---"
puts context_store.current_view

# 7. Run multiple turns to cause memory to update
puts "--- Starting Multi-Test Turn ---"
13.times do
  input_text = "Testing. Is it still working?"
  flow.run(
    msg: input_text,
    on_response: ->(resp : Mantle::Response) {
      puts "User: #{input_text}"
      if thinking = resp.thinking
        puts "\e[2m🤔 [Thinking]\n#{thinking}\n[Response]\e[0m"
      end
      puts "Bot: #{resp.content}"
    }
    )
end

# 7. Clear the context
puts "\n--- Clearing Context ---"
context_manager.clear_context

puts "\n--- Final Context State After Clearing ---"
puts context_store.current_view
  )

  # Consumer UI can watch Mantle::Status to know when background tasks occur
  if Mantle::Status.has?(:memory_consolidation)
    puts "UI UPDATE: Memory consolidation is currently running in the background..."
    Mantle::Status.remove(:memory_consolidation)
  end
end
