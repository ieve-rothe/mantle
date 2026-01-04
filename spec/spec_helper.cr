require "spec"
require "../src/mantle"

require "json"

class DummyContextStore < Mantle::ContextStore
  property system_prompt : String = "This is a test system prompt"
  property chat_context : String = ""
  def scratchpad : Hash(String, JSON::Any)
    Hash(String, JSON::Any).new
  end
end

class DummyFlow < Mantle::Flow
  # Only need base class methods from Mantle::Flow for now
end

class DummyClient < Mantle::Client
  def execute(prompt : String) : String
    "Simulated response from model"
  end
end

class DummyLogger < Mantle::Logger
  property output_file : String
  property log_file : String

  property last_message : String?
  property targeted_file : String?

  def initialize(@log_file : String)
    @output_file = @log_file
  end

  def log(message : String, label : String)
    @last_message = label + "\n" + message
    @targeted_file = @output_file
  end
end
