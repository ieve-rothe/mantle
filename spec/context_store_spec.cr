# spec/context_store_spec.cr
require "./spec_helper"

describe Mantle::EphemeralContextStore do
  
  describe "#initialize" do
    it "sets the initial system prompt and starts the context with it" do
      prompt = "You are a helpful assistant."
      store = Mantle::EphemeralContextStore.new(prompt)
      
      store.system_prompt.should eq(prompt)
      store.chat_context.should eq(prompt)
    end
  end

  describe "#add_message" do
    it "appends a labeled message to the existing context" do
      store = Mantle::EphemeralContextStore.new("Start.")
      store.add_message("Hello!", "User")
      
      store.chat_context.should eq("Start.[User]Hello!\n")
    end

    it "allows multiple messages to be stacked" do
      store = Mantle::EphemeralContextStore.new("System:")
      store.add_message("Ping", "User")
      store.add_message("Pong", "Assistant")
      
      store.chat_context.should eq("System:[User]Ping\n[Assistant]Pong\n")
    end
  end

  describe "#clear_context" do
    it "resets the chat_context back to only the system_prompt" do
      store = Mantle::EphemeralContextStore.new("Root Identity")
      store.add_message("I will be deleted", "User")
      
      store.clear_context
      
      store.chat_context.should eq("Root Identity")
    end
  end

  describe "Identity mutability" do
    it "allows updating the system_prompt after initialization" do
      store = Mantle::EphemeralContextStore.new("Old Prompt")
      store.system_prompt = "New Prompt"
      
      store.system_prompt.should eq("New Prompt")
      store.chat_context.should eq("Old Prompt\n[SYSTEM UPDATE]: Your core instructions have changed to New Prompt\n")
    end
  end
end