require "spec"
require "../src/mantle"

class DummyContextStore < Mantle::ContextStore
  property system_prompt : String = "This is a test system prompt"

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
    property last_message : String?
    property targeted_file : String?

    def log(message : String, label : String, file : String)
        @last_message = label + "\n" + message
        @targeted_file = file
    end
end
