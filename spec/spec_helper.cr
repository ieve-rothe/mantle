# spec/spec_helper.cr
require "spec"
require "../src/mantle"
require "json"

class DummyContextStore < Mantle::ContextStore
  property system_prompt : String = "System: Initial Prompt"
  property current_view : String = "System: Initial Prompt"

  def add_message(label : String, message : String)
    @current_view += "\n[#{label}] #{message}"
  end
end

class DummyMemoryStore < Mantle::LayeredMemoryStore
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
  def execute(prompt : String) : String
    "Simulated response"
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

  def log_message(role : Symbol, message : String, context : String)
    name = role == :user ? @user_name : @bot_name
    @last_message = "#{role} #{name} #{message}"
  end
end
