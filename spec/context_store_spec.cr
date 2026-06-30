# spec/context_store_spec.cr
require "./spec_helper"

# ------------------------------------------------------------------------------
# Ephemeral Sliding Context Store
# Should maintain last N messages in context
describe Mantle::Storage::EphemeralSlidingContextStore do
  describe "#initialize" do
    it "accepts a system prompt and a number of messages to keep in context" do
      # Arrange
      sys_prompt = "System Prompt"
      messages_to_keep = 3

      # Act
      store = Mantle::Storage::EphemeralSlidingContextStore.new(sys_prompt, messages_to_keep)

      # Assert
      store.system_prompt.should eq(sys_prompt)
      view = store.current_view
      view.should be_a(Array(Mantle::Message))
      view.size.should eq(1) # Only system message
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      store.messages_to_keep.should eq(messages_to_keep)
    end

    it "allows messages to be stacked up to the specified limit" do
      # Arrange
      sys_prompt = "System Prompt"
      messages_to_keep = 3
      store = Mantle::Storage::EphemeralSlidingContextStore.new(sys_prompt, messages_to_keep)

      # Act
      store.add_message("User", "Message1")
      store.add_message("Assistant", "Message2")
      store.add_message("User", "Message3")
      store.add_message("Assistant", "Message4")

      # Assert - Should have system message + last 3 conversation messages
      view = store.current_view
      view.size.should eq(4) # system + 3 messages (oldest dropped)
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      view[1].role.should eq("assistant")
      view[1].content.should eq("Message2")
      view[2].role.should eq("user")
      view[2].content.should eq("Message3")
      view[3].role.should eq("assistant")
      view[3].content.should eq("Message4")
    end

    it "supports 'tool' role for tool results" do
      # Arrange
      sys_prompt = "System Prompt"
      messages_to_keep = 5
      store = Mantle::Storage::EphemeralSlidingContextStore.new(sys_prompt, messages_to_keep)

      # Act
      store.add_message("User", "List files")
      store.add_message("Assistant", "") # Tool call (content may be empty)
      store.add_message("Tool", "Result: file1.txt, file2.txt")
      store.add_message("Assistant", "Here are the files")

      # Assert
      view = store.current_view
      view.size.should eq(5) # system + 4 messages
      view[0].role.should eq("system")
      view[1].role.should eq("user")
      view[2].role.should eq("assistant")
      view[3].role.should eq("tool")
      view[3].content.should eq("Result: file1.txt, file2.txt")
      view[4].role.should eq("assistant")
    end
  end

  describe "#clear" do
    it "removes all conversation messages" do
      # Arrange
      store = Mantle::Storage::EphemeralSlidingContextStore.new("System", 5)
      store.add_message("User", "Msg1")
      store.add_message("Assistant", "Msg2")

      # Act
      store.clear

      # Assert
      store.current_num_messages.should eq(0)
      view = store.current_view
      view.size.should eq(1) # Only system prompt remains
      view[0].role.should eq("system")
    end
  end

  describe "#update_system_prompt" do
    it "updates the system prompt in memory and reflects in current_view" do
      # Arrange
      store = Mantle::Storage::EphemeralSlidingContextStore.new("Old Prompt", 5)

      # Act
      store.update_system_prompt("New Prompt")

      # Assert
      store.system_prompt.should eq("New Prompt")
      view = store.current_view
      view[0].role.should eq("system")
      view[0].content.should eq("New Prompt")
    end
  end
end

# ------------------------------------------------------------------------------
# JSON Context Store
# Should maintain last N messages in context, loading them from JSON backend store
describe Mantle::Storage::JSONContextStore do
  describe "error handling" do
    it "logs an error when saving to an invalid path" do
      # Arrange
      test_file = "/sys/class/something_read_only.json"
      backend = Log::MemoryBackend.new
      Log.setup("mantle", :debug, backend)

      # Act
      # Using a read-only path will raise File::AccessDeniedError or similar,
      # which inherits from File::Error, so we expect an error log but no crash.
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      # Assert
      log_entries = backend.entries.select { |e| e.severity == Log::Severity::Error }
      log_entries.size.should be > 0
      log_entries[0].message.should contain("Failed to save context to #{test_file}")

      # Reset logger so other tests aren't affected
      Log.setup("mantle", :info, Log::IOBackend.new)
    end
  end

  describe "#initialize" do
    it "creates a new context store with a new JSON file if file doesn't exist" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "You are a test assistant."

      # Act
      store = Mantle::Storage::JSONContextStore.new(sys_prompt, test_file)

      # Assert
      store.system_prompt.should eq(sys_prompt)
      view = store.current_view
      view.should be_a(Array(Mantle::Message))
      view.size.should eq(1) # Only system message
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      File.exists?(test_file).should be_true

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "loads existing context from JSON file if it exists" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "Original system prompt"

      # Create a pre-existing context file with new message format
      existing_data = {
        "system_prompt" => sys_prompt,
        "messages"      => [
          {"role" => "user", "content" => "Hello"},
          {"role" => "assistant", "content" => "Hi there"},
        ],
      }
      File.write(test_file, existing_data.to_json)

      # Act
      store = Mantle::Storage::JSONContextStore.new(sys_prompt, test_file)

      # Assert
      view = store.current_view
      view.size.should eq(3) # system + 2 messages
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      view[1].role.should eq("user")
      view[1].content.should eq("Hello")
      view[2].role.should eq("assistant")
      view[2].content.should eq("Hi there")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#add_message" do
    it "adds a labeled message to the context" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::Storage::JSONContextStore.new("System:", test_file)

      # Act
      store.add_message("User", "Hello!")

      # Assert
      view = store.current_view
      view.size.should eq(2) # system + 1 message
      view[0].role.should eq("system")
      view[0].content.should eq("System:")
      view[1].role.should eq("user")
      view[1].content.should eq("Hello!")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "automatically saves context to JSON file after each message" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      # Act
      store.add_message("User", "TestMessage")

      # Assert - File should contain the new message
      File.exists?(test_file).should be_true
      json_content = JSON.parse(File.read(test_file))
      json_content["messages"].as_a.size.should eq(1)
      messages = json_content["messages"].as_a
      messages[0].as_h["role"].as_s.should eq("user")
      messages[0].as_h["content"].as_s.should eq("TestMessage")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#current_view" do
    it "returns message array with system prompt and conversation messages" do
      # Arrange
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::Storage::JSONContextStore.new("SysPrompt", test_file)

      # Act
      store.add_message("User", "Msg1")
      store.add_message("Bot", "Msg2")

      # Assert
      view = store.current_view
      view.size.should eq(3) # system + 2 messages
      view[0].role.should eq("system")
      view[0].content.should eq("SysPrompt")
      view[1].role.should eq("user")
      view[1].content.should eq("Msg1")
      view[2].role.should eq("assistant") # Bot normalized to assistant
      view[2].content.should eq("Msg2")

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
      store1 = Mantle::Storage::JSONContextStore.new(sys_prompt, test_file)
      store1.add_message("User", "Hello")
      store1.add_message("Assistant", "Hi")

      # Act - Create second instance with same file
      store2 = Mantle::Storage::JSONContextStore.new(sys_prompt, test_file)

      # Assert - Second instance should have same context
      view = store2.current_view
      view.size.should eq(3) # system + 2 messages
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      view[1].role.should eq("user")
      view[1].content.should eq("Hello")
      view[2].role.should eq("assistant")
      view[2].content.should eq("Hi")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#prune" do
    it "removes the oldest N messages and returns them" do
      # Arrange
      test_file = "/tmp/mantle_test_prune_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      store.add_message("User", "One")
      store.add_message("Assistant", "Two")
      store.add_message("User", "Three")
      store.add_message("Assistant", "Four")

      # Act - Prune the oldest 2 messages
      pruned_messages = store.prune(2)

      # Assert - Check return value
      pruned_messages.size.should eq(2)
      pruned_messages[0].role.should eq("user")
      pruned_messages[0].content.should eq("One")
      pruned_messages[1].role.should eq("assistant")
      pruned_messages[1].content.should eq("Two")

      # Assert - Check current state (only the last 2 should remain)
      view = store.current_view
      view.size.should eq(3) # system + 2 remaining messages
      view[0].role.should eq("system")
      view[1].role.should eq("user")
      view[1].content.should eq("Three")
      view[2].role.should eq("assistant")
      view[2].content.should eq("Four")

      # Assert - Check persistence (file should be updated)
      json_content = JSON.parse(File.read(test_file))
      json_content["messages"].as_a.size.should eq(2)
      json_content["messages"].as_a[0].as_h["content"].as_s.should eq("Three")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "handles pruning more messages than currently exist by returning all available" do
      # Arrange
      test_file = "/tmp/mantle_test_prune_overflow_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)
      store.add_message("User", "Only Message")

      # Act - Try to prune 100 messages when only 1 exists
      pruned = store.prune(100)

      # Assert
      pruned.size.should eq(1)
      pruned[0].role.should eq("user")
      pruned[0].content.should eq("Only Message")

      view = store.current_view
      view.size.should eq(1) # Only system message remains
      view[0].role.should eq("system")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#clear" do
    it "removes all conversation messages and updates the JSON file" do
      # Arrange
      test_file = "/tmp/mantle_test_clear_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)
      store.add_message("User", "Msg1")

      # Act
      store.clear

      # Assert
      store.current_num_messages.should eq(0)
      view = store.current_view
      view.size.should eq(1) # Only system prompt remains

      # Check persistence
      json_content = JSON.parse(File.read(test_file))
      json_content["messages"].as_a.size.should eq(0)

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#update_system_prompt" do
    it "updates the system prompt and persists it to the JSON file" do
      # Arrange
      test_file = "/tmp/mantle_test_update_sys_prompt_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("Old Prompt", test_file)

      # Act
      store.update_system_prompt("New Prompt")

      # Assert
      store.system_prompt.should eq("New Prompt")
      view = store.current_view
      view[0].role.should eq("system")
      view[0].content.should eq("New Prompt")

      # Check persistence
      json_content = JSON.parse(File.read(test_file))
      json_content["system_prompt"].as_s.should eq("New Prompt")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "ephemeral system prompt mode" do
    it "saves nil as the system prompt in the JSON file when persist_system_prompt is false" do
      # Arrange
      test_file = "/tmp/mantle_test_ephemeral_sys_prompt_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("Ephemeral System Prompt", test_file, persist_system_prompt: false)

      # Act
      store.add_message("User", "Hello")

      # Assert - JSON file should contain null/nil for system_prompt
      json_content = JSON.parse(File.read(test_file))
      json_content["system_prompt"]?.try(&.raw).should be_nil

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "preserves memory-initialized system prompt on load if file contains nil" do
      # Arrange
      test_file = "/tmp/mantle_test_ephemeral_sys_prompt_load_#{Time.utc.to_unix_ms}.json"

      # Save an ephemeral store context first (so system_prompt is nil/null in file)
      store1 = Mantle::Storage::JSONContextStore.new("Initial Temp Prompt", test_file, persist_system_prompt: false)
      store1.add_message("User", "Hello")

      # Act - Re-load using new instance with a different initialized prompt, persist_system_prompt: false
      store2 = Mantle::Storage::JSONContextStore.new("New Memory Prompt", test_file, persist_system_prompt: false)

      # Assert - The prompt should be the one passed to the constructor, not overridden to nil
      store2.system_prompt.should eq("New Memory Prompt")
      store2.current_view[0].content.should eq("New Memory Prompt")

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end

    it "does not persist system prompt even after update_system_prompt is called" do
      # Arrange
      test_file = "/tmp/mantle_test_ephemeral_sys_prompt_update_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("Initial", test_file, persist_system_prompt: false)

      # Act
      store.update_system_prompt("New Dynamic Prompt")

      # Assert - Updated in memory
      store.system_prompt.should eq("New Dynamic Prompt")
      store.current_view[0].content.should eq("New Dynamic Prompt")

      # Assert - Still null in file
      json_content = JSON.parse(File.read(test_file))
      json_content["system_prompt"]?.try(&.raw).should be_nil

      # Cleanup
      File.delete(test_file) if File.exists?(test_file)
    end
  end
end
