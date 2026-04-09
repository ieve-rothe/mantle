require "../src/mantle.cr"

# This example demonstrates how to set up a custom memory summarization prompt.
# It uses the `Squishifiers` module to build a summarizing callable, which
# the MemoryStore uses to condense old messages into a smaller format.

# 1. Setup Primitives
CONTEXT_FILE = "examples/test_context.json"
MEMORY_FILE = "examples/test_memory.json"
LOG_FILE     = "examples/test_log.txt"

# Clean up previous test files
[CONTEXT_FILE, MEMORY_FILE, LOG_FILE].each do |file|
  File.delete(file) if File.exists?(file)
end

# 2. Initialize Components
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

# Define the system prompt for the context window
context_store = Mantle::JSONContextStore.new(
  system_prompt: "You are an AI named Emma. You are speaking to Cam. We are running a diagnostic test within the LLM framework we built for which your main 'brain' application is a consumer.",
  context_file: CONTEXT_FILE
)

# Define a custom summarizing prompt
# By default, Squishifiers.build_basic_summarizer uses a generic summary prompt.
# Here we provide our own detailed prompt to enforce a specific POV ("Emma's first-person perspective").
summarizer_prompt = "You are the internal subconscious of an AI named Emma. Review the following recent chat log with Cam. Synthesize the interaction into a concise, 2-3 sentence narrative memory. Extract only actionable tasks, personal facts, and significant project milestones. Ignore casual banter, technical troubleshooting details, and greetings. Write the summary from Emma's first-person perspective."

# Build the squishifier using the prompt and client
squishy = Mantle::Squishifiers.build_basic_summarizer(client, summarizer_prompt)

# Feed the squishifier to the memory store
memory_store = Mantle::JSONLayeredMemoryStore.new(
  memory_file: MEMORY_FILE,
  layer_capacity: 5,
  layer_target: 2,
  squishifier: squishy
)

context_manager = Mantle::ContextManager.new(
  context_store: context_store,
  memory_store: memory_store,
  user_name: user_name,
  bot_name: bot_name,
  msg_target: 4,
  msg_hardmax: 8,
  strip_thinking_tags: true  # Strip <think></think> blocks from model responses
)

# 3. Build the Flow
flow = Mantle::ChatFlow.new(
  context_manager: context_manager,
  client: client,
  logger: logger
)

puts "--- Starting Realistic Memory Integration Test ---"

# The "Messy Human" Simulation Array
# This is designed to test if the model can extract facts from casual banter.
simulated_session = [
  "Hey Emma, just logging in. I'm planning to go for a run down in Ocean Beach later this afternoon.",
  "Yeah, I need to clear my head. I've been fighting with terminal ANSI codes in Crystal all morning. It was driving me crazy.",
  "I actually ended up dropping the Fancyline shard entirely and just using standard gets. It wraps perfectly now without duplicating text.",
  "Oh, before I forget, Sev needs his flea medication tomorrow morning. Remind me if I don't bring it up.",
  "Anyway, what do you think is the best way to handle JSON parsing for a deeply nested config file in Crystal?",
  "That makes sense. I'll probably just use the standard library's JSON::PullParser so it doesn't chew up memory.",
  "Did you see any weird errors in the dev log while I was working on that terminal stuff?",
  "Good to know. My brain is kind of fried from staring at hex codes.",
  "Alright, I'm going to step away from the keyboard for a bit and grab some coffee."
]

# Run the simulated conversation
simulated_session.each_with_index do |input_text, index|
  puts "\n[Turn #{index + 1}/#{simulated_session.size}]"
  
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
  
  # Optional: Sleep for a second so you can actually read the output 
  # as it streams, making it feel more like a real chat log.
  sleep(1.second) 
end

puts "\n--- Forcing/Waiting for Consolidation ---"
# If your threshold is higher than 9 messages, you might need to add a few 
# more dummy strings to the array, or manually trigger your consolidation 
# method here if Mantle exposes it.

puts "\n--- Final Context State (Layer 1 Check) ---"
puts context_store.current_view

puts "\n--- The Recall Test ---"
final_question = "I'm back. Just to check your memory—what was I planning to do this afternoon, and what do I need to do for the dog tomorrow?"

flow.run(
  msg: final_question,
  on_response: ->(resp : Mantle::Response) {
    puts "User: #{final_question}"
    if thinking = resp.thinking
      puts "\e[2m🤔 [Thinking]\n#{thinking}\n[Response]\e[0m"
    end
    puts "Bot: #{resp.content}"
  }
)