# spec/context_store_spec.cr
require "./spec_helper"

#------------------------------------------------------------------------------
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
      store.add_message("User", "Hello!")
      
      store.chat_context.should eq("Start.[User] Hello!\n")
    end

    it "allows multiple messages to be stacked" do
      store = Mantle::EphemeralContextStore.new("System:")
      store.add_message("User", "Ping")
      store.add_message("Assistant", "Pong")
      
      store.chat_context.should eq("System:[User] Ping\n[Assistant] Pong\n")
    end
  end

  describe "#clear_context" do
    it "resets the chat_context back to only the system_prompt" do
      store = Mantle::EphemeralContextStore.new("Root Identity")
      store.add_message("User", "I will be deleted")
      
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

#------------------------------------------------------------------------------
# Ephemeral Sliding Context Store
# Should maintain last N messages in context
describe Mantle::EphemeralSlidingContextStore do
  describe "#initialize" do
    it "accepts a system prompt and a number of messages to keep in context" do
      # Arrange
      sys_prompt = "System Prompt"
      messages_to_keep = 3

      # Act
      store = Mantle::EphemeralSlidingContextStore.new(sys_prompt, messages_to_keep)

      # Assert
      store.system_prompt.should eq(sys_prompt)
      store.chat_context.should eq(sys_prompt)
      store.messages_to_keep.should eq(messages_to_keep)
    end

    it "allows messages to be stacked up to the specified limit" do
      # Arrange
      sys_prompt = "System Prompt"
      messages_to_keep = 3
      store = Mantle::EphemeralSlidingContextStore.new(sys_prompt, messages_to_keep)

      # Act
      store.add_message("User", "Message1")
      store.add_message("Assistant", "Message2")
      store.add_message("User", "Message3")
      store.add_message("Assistant", "Message4")

      # Assert
      store.chat_context.should eq("System Prompt\n[Assistant] Message2\n[User] Message3\n[Assistant] Message4\n")
    end
  end
end

#------------------------------------------------------------------------------
# JSON Sliding Context Store
# Should maintain last N messages in context, loading them from JSON backend store
describe Mantle::JSONSlidingContextStore do
  describe "#initialize" do
    it "creates a new context store with a new JSON file if file doesn't exist" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "You are a test assistant."
      window_size = 5

      # Act
      store = Mantle::JSONSlidingContextStore.new(sys_prompt, window_size, test_file)

      # Assert
      store.system_prompt.should eq(sys_prompt)
      store.context_window_discrete.should eq(window_size)
      store.chat_context.should eq(sys_prompt)
      File.exists?(test_file).should be_true

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "loads existing context from JSON file if it exists" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "Original system prompt"
      window_size = 3

      # Create a pre-existing context file
      existing_data = {
        "system_prompt" => sys_prompt,
        "messages" => ["[User] Hello\n", "[Assistant] Hi there\n"]
      }
      File.write(test_file, existing_data.to_json)

      # Act
      store = Mantle::JSONSlidingContextStore.new(sys_prompt, window_size, test_file)

      # Assert
      store.chat_context.should eq("Original system prompt[User] Hello\n[Assistant] Hi there\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "loads only the last N messages when file has more than window size" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "System"
      window_size = 2

      # Create a file with 4 messages but window size is 2
      existing_data = {
        "system_prompt" => sys_prompt,
        "messages" => [
          "[User] Message1\n",
          "[Assistant] Response1\n",
          "[User] Message2\n",
          "[Assistant] Response2\n"
        ]
      }
      File.write(test_file, existing_data.to_json)

      # Act
      store = Mantle::JSONSlidingContextStore.new(sys_prompt, window_size, test_file)

      # Assert - should only have last 2 messages
      store.chat_context.should eq("System[User] Message2\n[Assistant] Response2\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#add_message" do
    it "adds a labeled message to the context" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONSlidingContextStore.new("System:", 5, test_file)

      # Act
      store.add_message("User", "Hello!")

      # Assert
      store.chat_context.should eq("System:[User] Hello!\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "maintains sliding window by dropping oldest messages" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONSlidingContextStore.new("System", 3, test_file)

      # Act - Add 5 messages with window size of 3
      store.add_message("User", "Message1")
      store.add_message("Assistant", "Response1")
      store.add_message("User", "Message2")
      store.add_message("Assistant", "Response2")
      store.add_message("User", "Message3")

      # Assert - Should only have last 3 messages
      expected = "System[User] Message2\n[Assistant] Response2\n[User] Message3\n"
      store.chat_context.should eq(expected)

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "automatically saves context to JSON file after each message" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONSlidingContextStore.new("System", 3, test_file)

      # Act
      store.add_message("User", "TestMessage")

      # Assert - File should contain the new message
      File.exists?(test_file).should be_true
      json_content = JSON.parse(File.read(test_file))
      json_content["messages"].as_a.size.should eq(1)
      json_content["messages"].as_a[0].should eq("[User] TestMessage\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#chat_context" do
    it "returns system prompt concatenated with messages" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONSlidingContextStore.new("SysPrompt", 3, test_file)

      # Act
      store.add_message("User", "Msg1")
      store.add_message("Bot", "Msg2")

      # Assert
      store.chat_context.should eq("SysPrompt[User] Msg1\n[Bot] Msg2\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "persistence across instances" do
    it "allows a new instance to resume from saved context" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "Persistent System"

      # First instance - create and add messages
      store1 = Mantle::JSONSlidingContextStore.new(sys_prompt, 3, test_file)
      store1.add_message("User", "Hello")
      store1.add_message("Assistant", "Hi")

      # Act - Create second instance with same file
      store2 = Mantle::JSONSlidingContextStore.new(sys_prompt, 3, test_file)

      # Assert - Second instance should have same context
      store2.chat_context.should eq("Persistent System[User] Hello\n[Assistant] Hi\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end
end

#------------------------------------------------------------------------------
# Ephemeral Sliding Context Store
# Should maintain last N messages in context, loading them from JSON backend store