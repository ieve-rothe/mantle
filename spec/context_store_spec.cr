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

  describe "turn replay & editing" do
    it "identifies purely conversational turns as replayable" do
      store = Mantle::Storage::EphemeralSlidingContextStore.new("System", 5)
      store.add_message("User", "Hello bot")
      store.add_message("Assistant", "Hello user")

      store.last_turn_replayable?.should be_true
      store.last_user_message.not_nil!.content.should eq("Hello bot")
      store.last_bot_message.not_nil!.content.should eq("Hello user")
    end

    it "rejects turns with tool calls or tool role messages" do
      store = Mantle::Storage::EphemeralSlidingContextStore.new("System", 5)
      tool_calls = [Mantle::Clients::ToolCall.new("call_1", Mantle::Clients::ToolCallFunction.new("test_tool", "{}"))]
      store.add_message("User", "Run tool")
      store.add_message("Assistant", "", tool_calls: tool_calls)
      store.add_message("Tool", "Result", tool_call_id: "call_1")
      store.add_message("Assistant", "Tool completed")

      store.last_turn_replayable?.should be_false
    end

    it "allows editing the last bot message in-place" do
      store = Mantle::Storage::EphemeralSlidingContextStore.new("System", 5)
      store.add_message("User", "Question")
      store.add_message("Assistant", "Original Answer")

      store.edit_last_bot_message("Edited Answer").should be_true
      store.last_bot_message.not_nil!.content.should eq("Edited Answer")
      view = store.current_view
      view.last.content.should eq("Edited Answer")
    end

    it "pops the last turn for replay returning original user input" do
      store = Mantle::Storage::EphemeralSlidingContextStore.new("System", 5)
      store.add_message("User", "Original Question")
      store.add_message("Assistant", "Answer")

      popped_prompt = store.pop_last_turn_for_replay
      popped_prompt.should eq("Original Question")
      store.current_num_messages.should eq(0)
      store.last_turn_replayable?.should be_false
    end
  end

  describe "#prune_to_tokens" do
    it "returns an empty array and leaves messages intact when target_tokens is very high" do
      # Arrange
      store = Mantle::Storage::EphemeralSlidingContextStore.new("System", 5)
      store.add_message("User", "Msg1")
      store.add_message("Assistant", "Msg2")

      # Act
      pruned = store.prune_to_tokens(10000)

      # Assert
      pruned.should be_empty
      view = store.current_view
      view.size.should eq(3) # system + 2 messages
      view[1].role.should eq("user")
      view[1].content.should eq("Msg1")
      view[2].role.should eq("assistant")
      view[2].content.should eq("Msg2")
    end
  end
end

# ------------------------------------------------------------------------------
# JSON Context Store (Node Graph)
# ------------------------------------------------------------------------------
describe Mantle::Storage::JSONContextStore do
  describe "error handling" do
    it "logs an error when saving to an invalid path" do
      test_file = "/sys/class/something_read_only.json"
      backend = Log::MemoryBackend.new
      Log.setup("mantle", :debug, backend)

      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      log_entries = backend.entries.select { |e| e.severity == Log::Severity::Error }
      log_entries.size.should be > 0
      log_entries[0].message.should contain("Failed to save context to #{test_file}")

      Log.setup("mantle", :info, Log::IOBackend.new)
    end
  end

  describe "#initialize" do
    it "creates a new context store with a new JSON file if file doesn't exist" do
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "You are a test assistant."

      store = Mantle::Storage::JSONContextStore.new(sys_prompt, test_file)

      store.system_prompt.should eq(sys_prompt)
      view = store.current_view
      view.should be_a(Array(Mantle::Message))
      view.size.should eq(1) # Only system message
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      File.exists?(test_file).should be_true

      File.delete(test_file) if File.exists?(test_file)
    end

    it "loads existing graph context from JSON file if it exists" do
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      sys_prompt = "Original system prompt"

      node1 = Mantle::Storage::ContextNode.new(
        message: Mantle::Message.new("user", "Hello"),
        token_count: 5,
        id: "node_1"
      )
      node2 = Mantle::Storage::ContextNode.new(
        message: Mantle::Message.new("assistant", "Hi there"),
        token_count: 5,
        parent_id: "node_1",
        id: "node_2"
      )

      existing_data = {
        "schema_version" => 1,
        "active_leaf_id" => "node_2",
        "nodes" => {
          "node_1" => node1,
          "node_2" => node2
        }
      }
      File.write(test_file, existing_data.to_json)

      store = Mantle::Storage::JSONContextStore.new(sys_prompt, test_file)

      view = store.current_view
      view.size.should eq(3) # system + 2 messages
      view[0].role.should eq("system")
      view[0].content.should eq(sys_prompt)
      view[1].role.should eq("user")
      view[1].content.should eq("Hello")
      view[2].role.should eq("assistant")
      view[2].content.should eq("Hi there")

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#add_message" do
    it "adds a labeled message node to the context graph" do
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::Storage::JSONContextStore.new("System:", test_file)

      store.add_message("User", "Hello!")

      view = store.current_view
      view.size.should eq(2) # system + 1 message
      view[0].role.should eq("system")
      view[0].content.should eq("System:")
      view[1].role.should eq("user")
      view[1].content.should eq("Hello!")

      File.delete(test_file) if File.exists?(test_file)
    end

    it "automatically saves node graph context atomically to JSON file after each message" do
      test_file = "/tmp/mantle_test_context_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      store.add_message("User", "TestMessage")

      File.exists?(test_file).should be_true
      json_content = JSON.parse(File.read(test_file))
      json_content["schema_version"].as_i.should eq(1)
      nodes = json_content["nodes"].as_h
      nodes.size.should eq(1)
      leaf_id = json_content["active_leaf_id"].as_s
      nodes[leaf_id].as_h["message"].as_h["content"].as_s.should eq("TestMessage")

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "Serialization Round-Trip & RFC_3339" do
    it "serializes ContextNode with RFC_3339 time format for byte-identical round trips" do
      msg = Mantle::Message.new("user", "Roundtrip test")
      time = Time.utc(2026, 7, 27, 16, 0, 0)
      node = Mantle::Storage::ContextNode.new(message: msg, token_count: 10, ts: time, id: "node_rt")

      json = node.to_json
      node_restored = Mantle::Storage::ContextNode.from_json(json)

      node_restored.id.should eq(node.id)
      node_restored.ts.should eq(node.ts)
      node_restored.to_json.should eq(json)
    end
  end

  describe "Blob Side-Store" do
    it "writes assembled context to write-once side directory .contexts/blobs/" do
      test_file = "/tmp/mantle_blob_test_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)
      full_context = "System Prompt + Large Assembled Context String"

      node = store.add_message("User", "Hello", assembled_context: full_context)

      node.assembled_context_sha.should_not be_nil
      sha = node.assembled_context_sha.not_nil!

      read_back = store.read_assembled_context(sha)
      read_back.should eq(full_context)

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "Branch Isolation & Leaf Switching" do
    it "supports branching where two children share a parent but have disjoint tails" do
      test_file = "/tmp/mantle_branch_test_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      root_node = store.add_message("User", "Root Question")
      branch1_node = store.add_message("Assistant", "Answer Path 1")

      # Switch back to root and create branch 2
      store.set_active_leaf(root_node.id)
      branch2_node = store.add_message("Assistant", "Answer Path 2")

      anc1 = store.ancestors(branch1_node.id)
      anc2 = store.ancestors(branch2_node.id)

      anc1.map(&.message.content).should eq(["Root Question", "Answer Path 1"])
      anc2.map(&.message.content).should eq(["Root Question", "Answer Path 2"])

      # Verify active view reflects branch 2
      view = store.current_view
      view.map(&.content).should eq(["System", "Root Question", "Answer Path 2"])

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#prune_to_tokens" do
    it "prunes oldest messages cleanly from active branch to reach target tokens" do
      test_file = "/tmp/mantle_prune_tokens_test_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      n1 = store.add_message("User", "Msg 1")
      n2 = store.add_message("Assistant", "Msg 2")
      n3 = store.add_message("User", "Msg 3")

      pruned = store.prune_to_tokens(2)
      pruned.size.should be >= 1

      view = store.current_view
      view.any? { |m| m.content == "Msg 1" }.should be_false

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "Turn Grouping Traversal" do
    it "returns entire semantic turns when get_node_and_neighbors is called with turns: true" do
      test_file = "/tmp/mantle_turns_test_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      tool_calls = [Mantle::Clients::ToolCall.new("c1", Mantle::Clients::ToolCallFunction.new("fn", "{}"))]
      store.add_message("User", "Turn 1 Prompt", turn_id: "turn_1")
      store.add_message("Assistant", "", tool_calls: tool_calls, turn_id: "turn_1")
      tool_node = store.add_message("Tool", "Tool Result 1", tool_call_id: "c1", turn_id: "turn_1")
      store.add_message("Assistant", "Turn 1 Final Answer", turn_id: "turn_1")

      neighbors = store.get_node_and_neighbors(tool_node.id, k: 0, turns: true)
      neighbors.size.should eq(4)
      neighbors.all? { |n| n.turn_id == "turn_1" }.should be_true

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#prune" do
    it "prunes oldest messages cleanly from active branch" do
      test_file = "/tmp/mantle_test_prune_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      store.add_message("User", "One")
      store.add_message("Assistant", "Two")
      store.add_message("User", "Three")
      store.add_message("Assistant", "Four")

      pruned_messages = store.prune(2)
      pruned_messages.size.should eq(2)
      pruned_messages[0].content.should eq("One")
      pruned_messages[1].content.should eq("Two")

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#clear" do
    it "removes all conversation messages and updates the JSON file" do
      test_file = "/tmp/mantle_test_clear_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)
      store.add_message("User", "Msg1")

      store.clear

      store.current_num_messages.should eq(0)
      view = store.current_view
      view.size.should eq(1)

      json_content = JSON.parse(File.read(test_file))
      json_content["nodes"].as_h.size.should eq(0)

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "#update_system_prompt" do
    it "updates the system prompt and persists it to memory" do
      test_file = "/tmp/mantle_test_update_sys_prompt_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("Old Prompt", test_file)

      store.update_system_prompt("New Prompt")

      store.system_prompt.should eq("New Prompt")
      view = store.current_view
      view[0].role.should eq("system")
      view[0].content.should eq("New Prompt")

      File.delete(test_file) if File.exists?(test_file)
    end
  end

  describe "JSONContextStore turn replay & editing" do
    it "edits last bot response by creating a new branch and updating active_leaf_id" do
      test_file = "/tmp/mantle_test_json_replay_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      store.add_message("User", "What is 2+2?")
      store.add_message("Assistant", "4")

      store.last_turn_replayable?.should be_true
      store.edit_last_bot_message("2+2 equals 4.").should be_true

      view = store.current_view
      view.last.content.should eq("2+2 equals 4.")

      File.delete(test_file) if File.exists?(test_file)
    end

    it "pops last turn for replay by rewinding active_leaf_id" do
      test_file = "/tmp/mantle_test_json_pop_#{Time.utc.to_unix_ms}.json"
      store = Mantle::Storage::JSONContextStore.new("System", test_file)

      store.add_message("User", "Old Query")
      store.add_message("Assistant", "Old Response")

      popped = store.pop_last_turn_for_replay
      popped.should eq("Old Query")

      store.current_num_messages.should eq(0)

      File.delete(test_file) if File.exists?(test_file)
    end
  end
end
