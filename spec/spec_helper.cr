# spec/spec_helper.cr
require "spec"
require "../src/mantle"
require "json"

class DummyContextStore < Mantle::ContextStore
  property system_prompt : String = "System: Initial Prompt"
  property messages : Array(Hash(String, String)) = [] of Hash(String, String)

  def initialize(@system_prompt : String = "System: Initial Prompt")
    super(@system_prompt)
  end

  def current_view : Array(Hash(String, String))
    result = [] of Hash(String, String)
    result << {"role" => "system", "content" => @system_prompt} unless @system_prompt.empty?
    result.concat(@messages)
    result
  end

  def add_message(label : String, message : String)
    role = normalize_role(label)
    @messages << {"role" => role, "content" => message}
    @current_num_messages = @messages.size
  end
end

class DummyMemoryStore < Mantle::JSONLayeredMemoryStore
  def initialize
    # Initialize parent class properties with dummy test values
    @memory_file = "/tmp/dummy_memory_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
    @layer_capacity = 10
    @layer_target = 5
    @squishifier = ->(messages : Array(String)) : String { "" }
    @ingest_step_size = (@layer_capacity - @layer_target)
  end

  def current_view
    ""
  end
end

class DummyContextManager < Mantle::ContextManager
  def initialize(context_store : Mantle::ContextStore)
    super(context_store, DummyMemoryStore.new, "User", "Assistant")
  end

  def handle_user_message(msg : String)
    @context_store.add_message("User", msg)
  end

  def handle_bot_message(msg : String)
    @context_store.add_message("Assistant", msg)
  end
end

class DummyClient < Mantle::Client
  def execute(messages : Array(Hash(String, String)), tools : Array(Mantle::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Response
    on_chunk.call("Simulated response")
    Mantle::Response.new(content: "Simulated response", tool_calls: nil)
  end
end

class DummyLogger < Mantle::Logger
  property last_message : String? = nil

  def initialize(user_name : String = "User", bot_name : String = "Assistant")
    super(user_name, bot_name)
  end

  def log(label : String, message : String)
    @last_message = "#{label} #{message}"
  end

  def log_message(role : Symbol, message : String, context : String, thinking : String? = nil)
    name = role == :user ? @user_name : @bot_name
    @last_message = "#{role} #{name} #{message}"
  end

  def log_api_payloads(request : String, response : String)
    # No-op for tests
  end
end

####

# Test helper: deterministic squishifier for predictable outputs
def make_deterministic_squishifier
  ->(messages : Array(String)) : String {
    # Extract just the message content (strip labels and newlines for clarity)
    content = messages.map { |msg| msg.strip }.join(" | ")
    "Summary of #{messages.size} messages: #{content}"
  }
end

# Test helper: create unique temp file path
def temp_file_path
  "/tmp/mantle_memory_test_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
end
