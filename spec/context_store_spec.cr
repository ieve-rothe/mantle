# spec/context_store_spec.cr
require "./spec_helper"

# ------------------------------------------------------------------------------
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
      store.current_view.should eq(sys_prompt)
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
      store.current_view.should eq("System Prompt\n[Assistant] Message2\n[User] Message3\n[Assistant] Message4\n")
    end
  end
end

# ------------------------------------------------------------------------------
# JSON Context Store
# Should maintain last N messages in context, loading them from JSON backend store
describe Mantle::JSONContextStore do
  describe "#initialize" do
    it "creates a new context store with a new JSON file if file doesn't exist" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "You are a test assistant."

      # Act
      store = Mantle::JSONContextStore.new(sys_prompt, test_file)

      # Assert
      store.system_prompt.should eq(sys_prompt)
      store.current_view.should eq(sys_prompt)
      File.exists?(test_file).should be_true

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "loads existing context from JSON file if it exists" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "Original system prompt"

      # Create a pre-existing context file
      existing_data = {
        "system_prompt" => sys_prompt,
        "messages"      => ["[User] Hello\n", "[Assistant] Hi there\n"],
      }
      File.write(test_file, existing_data.to_json)

      # Act
      store = Mantle::JSONContextStore.new(sys_prompt, test_file)

      # Assert
      store.current_view.should eq("Original system prompt[User] Hello\n[Assistant] Hi there\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#add_message" do
    it "adds a labeled message to the context" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONContextStore.new("System:", test_file)

      # Act
      store.add_message("User", "Hello!")

      # Assert
      store.current_view.should eq("System:[User] Hello!\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "automatically saves context to JSON file after each message" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONContextStore.new("System", test_file)

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

  describe "#current_view" do
    it "returns system prompt concatenated with messages" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::JSONContextStore.new("SysPrompt", test_file)

      # Act
      store.add_message("User", "Msg1")
      store.add_message("Bot", "Msg2")

      # Assert
      store.current_view.should eq("SysPrompt[User] Msg1\n[Bot] Msg2\n")

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
      store1 = Mantle::JSONContextStore.new(sys_prompt, test_file)
      store1.add_message("User", "Hello")
      store1.add_message("Assistant", "Hi")

      # Act - Create second instance with same file
      store2 = Mantle::JSONContextStore.new(sys_prompt, test_file)

      # Assert - Second instance should have same context
      store2.current_view.should eq("Persistent System[User] Hello\n[Assistant] Hi\n")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end
  describe "#prune" do
    it "removes the oldest N messages and returns them" do
      # Arrange
      test_file = "/tmp/mantle_test_prune_#{Time.utc.to_unix_ms}.json"
      store = Mantle::JSONContextStore.new("System", test_file)

      store.add_message("User", "One")
      store.add_message("Assistant", "Two")
      store.add_message("User", "Three")
      store.add_message("Assistant", "Four")

      # Act - Prune the oldest 2 messages
      pruned_messages = store.prune(2)

      # Assert - Check return value
      pruned_messages.size.should eq(2)
      pruned_messages[0].should contain("One")
      pruned_messages[1].should contain("Two")

      # Assert - Check current state (only the last 2 should remain)
      store.current_view.should eq("System[User] Three\n[Assistant] Four\n")

      # Assert - Check persistence (file should be updated)
      json_content = JSON.parse(File.read(test_file))
      json_content["messages"].as_a.size.should eq(2)
      json_content["messages"].as_a[0].as_s.should contain("Three")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "handles pruning more messages than currently exist by returning all available" do
      # Arrange
      test_file = "/tmp/mantle_test_prune_overflow_#{Time.utc.to_unix_ms}.json"
      store = Mantle::JSONContextStore.new("System", test_file)
      store.add_message("User", "Only Message")

      # Act - Try to prune 100 messages when only 1 exists
      pruned = store.prune(100)

      # Assert
      pruned.size.should eq(1)
      store.current_view.should eq("System")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end
end

# ------------------------------------------------------------------------------
# Ephemeral Sliding Context Store
# Should maintain last N messages in context, loading them from JSON backend store
