# spec/spec_helper.cr
require "spec"
require "../src/mantle"
require "json"

class DummyContextStore < Mantle::ContextStore
  property system_prompt : String = "System: Initial Prompt"
  property chat_context : String = "System: Initial Prompt"

  def add_message(label : String, message : String)
    @chat_context += "\n[#{label}] #{message}"
  end
end

class DummyClient < Mantle::Client
  def execute(prompt : String) : String
    "Simulated response"
  end
end

class DummyLogger < Mantle::Logger
  property last_message : String? = nil

  def initialize(@log_file : String = "test.log")
  end

  def log(label : String, message : String)
    @last_message = "#{label} #{message}"
  end

  def log_context(message : String)
    # Only implemented in DetailedLogger
  end

  def log_user_message(message : String)
    # Only implemented in DetailedLogger
  end

  def log_bot_message(message : String)
    # Only implemented in DetailedLogger
  end
end