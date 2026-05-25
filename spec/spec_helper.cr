require "spec"
require "../src/mantle"
require "json"

class DummyContextStore < Mantle::Storage::ContextStore
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

class DummyMemoryStore < Mantle::Storage::JSONLayeredMemoryStore
  def initialize
    # Initialize parent class properties with dummy test values
    @memory_file = "/tmp/dummy_memory_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
    @layer_token_capacity = 100
    @layer_token_target = 50
    @squishifier = ->(messages : Array(String)) : String { "" }
  end

  def current_view
    ""
  end
end

class DummyContextManager < Mantle::Storage::ContextManager
  def initialize(context_store : Mantle::Storage::ContextStore)
    super(context_store, DummyMemoryStore.new, "User", "Assistant")
  end

  def handle_user_message(msg : String)
    @context_store.add_message("User", msg)
  end

  def handle_bot_message(msg : String)
    @context_store.add_message("Assistant", msg)
  end
end

class DummyClient < Mantle::Clients::Client
  def execute(messages : Array(Hash(String, String)), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    on_chunk.call("Simulated response")
    Mantle::Clients::Response.new(content: "Simulated response", tool_calls: nil)
  end
end

class DummyLogger < Mantle::Support::Logger
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
