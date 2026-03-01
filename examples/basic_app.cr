require "../src/mantle.cr"

# Basic example showing implementation of a ChatFlow using a JSONSlidingContextStore, LayeredMemoryStore coordinated with a ContextManager

# 1. Setup Primitives
CONTEXT_FILE = "test_context.json"
LOG_FILE     = "test_log.txt"

# 2. Initialize Components
model_config = Mantle::ModelConfig.new(
  model_name: "gpt-oss:20b",
  stream: false,
  temperature: 1.0,
  top_p: 0.85,
  max_tokens: 5000,
  api_url: "http://localhost:11434/api/generate"
)

user_name = "Username"
bot_name = "Botname"

client = Mantle::LlamaClient.new(model_config)
logger = Mantle::FileLogger.new(LOG_FILE, user_name, bot_name)
context_store = Mantle::JSONContextStore.new(
  system_prompt: "Respond to the test.",
  file_path: CONTEXT_FILE
)
memory_store = Mantle::LayeredMemoryStore.new
context_manager = Mantle::ContextManager.new(
  context_store,
  memory_store,
  user_name,
  bot_name
)

# 3. Build the Flow
flow = Mantle::ChatFlow.new(
  context_manager: context_manager,
  client: client,
  logger: logger
)

# 4. Execute a single turn
puts "--- Starting Test Turn ---"
input_text = "Hello! Are you running correctly?"

flow.run(
  msg: input_text,
  on_response: ->(msg : String) {
    puts "User: #{input_text}"
    puts "Bot: #{msg}"
  }
)

# 5. Verify the Context was updated
puts "\n--- Final Context State ---"
puts store.current_view
