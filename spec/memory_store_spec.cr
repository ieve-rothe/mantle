require "./spec_helper"
require "file_utils"

describe Mantle::JSONLayeredMemoryStore do
  describe "#initialize" do
    it "creates a new memory store with empty layers" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Act
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 10,
        layer_target: 4,
        squishifier: squishifier
      )

      # Assert
      store.layer_capacity.should eq(10)
      store.layer_target.should eq(4)
      store.current_view.should eq("")

      # Cleanup
      File.delete(file_path) if File.exists?(file_path)
    end

    it "creates a JSON file on initialization if it doesn't exist" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Act
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 10,
        layer_target: 4,
        squishifier: squishifier
      )

      # Assert
      File.exists?(file_path).should be_true

      # Cleanup
      File.delete(file_path)
    end

    it "loads existing data from JSON file if present" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Create initial store and add some data
      store1 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)
      store1.ingest(["[User] Hello\n", "[Bot] Hi there\n"])

      # Act - Create new store pointing to same file
      store2 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Assert - Should have loaded the data
      store2.current_view.should_not eq("")
      store2.current_view.should contain("Summary of 2 messages")

      # Cleanup
      File.delete(file_path)
    end

    it "validates that layer_target < layer_capacity" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Act & Assert - Should raise error when target >= capacity
      expect_raises(Exception) do
        Mantle::JSONLayeredMemoryStore.new(
          memory_file: file_path,
          layer_capacity: 5,
          layer_target: 10,
          squishifier: squishifier
        )
      end

      # Cleanup
      File.delete(file_path) if File.exists?(file_path)
    end

    it "validates that layer_target is positive" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Act & Assert
      expect_raises(Exception) do
        Mantle::JSONLayeredMemoryStore.new(
          memory_file: file_path,
          layer_capacity: 10,
          layer_target: 0,
          squishifier: squishifier
        )
      end

      # Cleanup
      File.delete(file_path) if File.exists?(file_path)
    end
  end

  describe "#ingest" do
    it "squishifies messages and adds them to Layer 0" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Act
      store.ingest(["[User] Hello\n", "[Bot] Hi there\n"])

      # Assert
      view = store.current_view
      view.should contain("=== Memory Layer 0 ===")
      view.should contain("Summary of 2 messages")
      view.should contain("[User] Hello")
      view.should contain("[Bot] Hi there")

      # Cleanup
      File.delete(file_path)
    end

    it "adds timestamp to squished summary" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Act
      store.ingest(["[User] Test message\n"])

      # Assert - Should have timestamp format [YYYY-MM-DD HH:MM]
      view = store.current_view
      view.should match(/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}\]/)

      # Cleanup
      File.delete(file_path)
    end

    it "handles multiple ingests into Layer 0" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Act
      store.ingest(["[User] First\n"])
      store.ingest(["[Bot] Second\n"])
      store.ingest(["[User] Third\n"])

      # Assert - Should have 3 separate summaries in Layer 0
      view = store.current_view
      view.should contain("Summary of 1 messages: [User] First")
      view.should contain("Summary of 1 messages: [Bot] Second")
      view.should contain("Summary of 1 messages: [User] Third")

      # Cleanup
      File.delete(file_path)
    end

    it "persists to JSON after each ingest" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Act
      store.ingest(["[User] Persistence test\n"])

      # Assert - Create new store to verify persistence
      store2 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)
      store2.current_view.should contain("Persistence test")

      # Cleanup
      File.delete(file_path)
    end

    it "handles empty message array gracefully" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Act - Ingest empty array (edge case)
      store.ingest([] of String)

      # Assert - Should not crash, view should be empty
      store.current_view.should eq("")

      # Cleanup
      File.delete(file_path)
    end
  end

  describe "fault tolerance - squishifier failures" do
    it "keeps messages in ingest_pending when squishifier fails" do
      # Arrange
      file_path = temp_file_path
      call_count = 0
      failing_squishifier = ->(messages : Array(String)) : String {
        call_count += 1
        raise Exception.new("LLM unavailable")
      }
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, failing_squishifier)

      # Act - Attempt to ingest
      store.ingest(["[User] Test message\n"])

      # Assert - Messages should remain in ingest_pending
      store.ingest_pending.size.should eq(1)
      store.ingest_pending[0].should eq("[User] Test message\n")
      # Layer 0 gets created but should be empty
      store.layers.size.should eq(1)
      store.layers[0].should be_empty
      store.current_view.should eq("")

      # Cleanup
      File.delete(file_path)
    end

    it "persists failed messages to JSON for retry" do
      # Arrange
      file_path = temp_file_path
      failing_squishifier = ->(messages : Array(String)) : String {
        raise Exception.new("Network error")
      }
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, failing_squishifier)

      # Act - Attempt to ingest, which will fail
      store.ingest(["[User] Message 1\n", "[User] Message 2\n"])

      # Assert - Should be persisted to JSON
      json_content = File.read(file_path)
      data = JSON.parse(json_content)
      data["ingest_pending"].as_a.size.should eq(2)
      data["ingest_pending"].as_a[0].should eq("[User] Message 1\n")
      data["ingest_pending"].as_a[1].should eq("[User] Message 2\n")

      # Cleanup
      File.delete(file_path)
    end

    it "processes pending messages on retry with working squishifier" do
      # Arrange
      file_path = temp_file_path
      failing_squishifier = ->(messages : Array(String)) : String {
        raise Exception.new("Temporary failure")
      }
      store1 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, failing_squishifier)

      # Act - First attempt fails
      store1.ingest(["[User] Pending message\n"])
      store1.ingest_pending.size.should eq(1)

      # Create new store with working squishifier (simulates retry after LLM recovers)
      working_squishifier = make_deterministic_squishifier
      store2 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, working_squishifier)

      # Trigger processing by adding new message
      store2.ingest(["[User] New message\n"])

      # Assert - Both pending and new message should be processed together
      store2.ingest_pending.should be_empty
      store2.layers[0].size.should eq(1)
      # Both messages in one summary (processed together)
      view = store2.current_view
      view.should contain("Pending message")
      view.should contain("New message")
      view.should contain("Summary of 2 messages")

      # Cleanup
      File.delete(file_path)
    end

    it "handles partial failures in batch processing" do
      # Arrange
      file_path = temp_file_path
      call_count = 0
      # Fail on first call, succeed on subsequent calls
      sometimes_failing_squishifier = ->(messages : Array(String)) : String {
        call_count += 1
        if call_count == 1
          raise Exception.new("First call fails")
        end
        messages.map { |msg| msg.strip }.join(" | ")
      }
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, sometimes_failing_squishifier)

      # Act - First ingest fails, second succeeds and processes both
      store.ingest(["[User] Message 1\n"])
      store.ingest(["[User] Message 2\n"])

      # Assert - Second ingest processes all pending messages (both Msg1 and Msg2 together)
      store.ingest_pending.should be_empty
      store.layers[0].size.should eq(1)
      # Both messages should be in the single summary
      view = store.current_view
      view.should contain("Message 1")
      view.should contain("Message 2")

      # Cleanup
      File.delete(file_path)
    end

    it "continues normal operation after squishifier recovers" do
      # Arrange
      file_path = temp_file_path
      call_count = 0
      # Fail first 2 calls, then work normally
      recovering_squishifier = ->(messages : Array(String)) : String {
        call_count += 1
        if call_count <= 2
          raise Exception.new("Temporary outage")
        end
        "Summary of #{messages.size} messages: #{messages.map { |msg| msg.strip }.join(" | ")}"
      }
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, recovering_squishifier)

      # Act - Two failures, then success
      store.ingest(["[User] Msg1\n"])  # Fails
      store.ingest(["[User] Msg2\n"])  # Fails again
      store.ingest(["[User] Msg3\n"])  # Succeeds, processes all 3 together

      # Assert - All messages eventually processed in one summary
      store.ingest_pending.should be_empty
      store.layers[0].size.should eq(1)
      view = store.current_view
      view.should contain("Summary of 3 messages")
      view.should contain("Msg1")
      view.should contain("Msg2")
      view.should contain("Msg3")

      # Cleanup
      File.delete(file_path)
    end
  end

  describe "#consolidate_layer - Layer 0 to Layer 1" do
    it "consolidates Layer 0 when reaching capacity" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 5,
        layer_target: 2,
        squishifier: squishifier
      )

      # Act - Add 5 ingests to reach capacity
      5.times do |i|
        store.ingest(["[User] Message #{i}\n"])
      end

      # Assert - Should have consolidated 3 oldest messages to Layer 1
      # Layer 1 should exist and contain a summary
      view = store.current_view
      view.should contain("=== Memory Layer 1 ===")
      view.should contain("Summary of 3 messages")

      # Layer 0 should have 2 remaining messages (the most recent)
      # Extract just Layer 0's section
      layer0_section = view.split("=== Memory Layer 0 ===")[1]
      layer0_section.should contain("Message 3")
      layer0_section.should contain("Message 4")
      # Old messages should only be in Layer 1, not in Layer 0
      layer0_section.should_not contain("Summary of 1 messages: [User] Message 0")
      layer0_section.should_not contain("Summary of 1 messages: [User] Message 1")
      layer0_section.should_not contain("Summary of 1 messages: [User] Message 2")

      # Cleanup
      File.delete(file_path)
    end

    it "triggers consolidation immediately when capacity is exceeded" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 1,
        squishifier: squishifier
      )

      # Act - Add exactly 3 messages (reaching capacity)
      3.times do |i|
        store.ingest(["[User] Msg #{i}\n"])
      end

      # Assert - Consolidation should have happened
      view = store.current_view
      view.should contain("=== Memory Layer 1 ===")

      # Cleanup
      File.delete(file_path)
    end

    it "preserves most recent messages in Layer 0 after consolidation" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 6,
        layer_target: 3,
        squishifier: squishifier
      )

      # Act - Add messages with identifiable content
      store.ingest(["[User] Oldest\n"])
      store.ingest(["[User] Old\n"])
      store.ingest(["[User] Middle\n"])
      store.ingest(["[User] Recent1\n"])
      store.ingest(["[User] Recent2\n"])
      store.ingest(["[User] Newest\n"]) # This triggers consolidation

      # Assert - Most recent 3 should be in Layer 0
      view = store.current_view
      view.should contain("Recent1")
      view.should contain("Recent2")
      view.should contain("Newest")

      # Oldest 3 should be consolidated to Layer 1
      layer1_section = view.split("=== Memory Layer 1 ===")[1].split("=== Memory Layer 0 ===")[0]
      layer1_section.should contain("Oldest")
      layer1_section.should contain("Old")
      layer1_section.should contain("Middle")

      # Cleanup
      File.delete(file_path)
    end
  end

  describe "#consolidate_layer - Multi-layer cascading" do
    it "cascades consolidation from Layer 1 to Layer 2" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 1,
        squishifier: squishifier
      )

      # Act - Trigger multiple consolidations
      # First 3 ingests: Layer 0 consolidates to Layer 1 (2 messages consolidated)
      3.times { |i| store.ingest(["[User] Batch1-#{i}\n"]) }

      # Next 3 ingests: Layer 0 consolidates again, adding to Layer 1
      3.times { |i| store.ingest(["[User] Batch2-#{i}\n"]) }

      # Next 3 ingests: Layer 0 consolidates again, adding to Layer 1
      # Now Layer 1 has 3 summaries, triggers consolidation to Layer 2
      3.times { |i| store.ingest(["[User] Batch3-#{i}\n"]) }

      # Assert - Should have Layer 2 now
      view = store.current_view
      view.should contain("=== Memory Layer 2 ===")
      view.should contain("=== Memory Layer 1 ===")
      view.should contain("=== Memory Layer 0 ===")

      # Layer 2 should contain consolidated summaries
      view.should contain("Summary of 2 messages")

      # Cleanup
      File.delete(file_path)
    end

    it "creates layers dynamically as needed" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 8,
        layer_target: 5,
        squishifier: squishifier
      )

      # Act - Trigger cascading through multiple layers
      # With capacity=8, target=5: ingest_step_size=3
      # Need enough ingests to fill Layer 0, consolidate to Layer 1, then Layer 1 to Layer 2
      # With these parameters, need significant ingests to cascade deep enough
      60.times { |i| store.ingest(["[User] Message #{i}\n"]) }

      # Assert - Should have created multiple layers
      view = store.current_view
      # At minimum, should have Layers 0, 1, 2
      view.should contain("=== Memory Layer 0 ===")
      view.should contain("=== Memory Layer 1 ===")
      view.should contain("=== Memory Layer 2 ===")

      # Cleanup
      File.delete(file_path)
    end

    it "handles recursive consolidation correctly" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 2,
        squishifier: squishifier
      )

      # Act - Add enough messages to trigger cascading
      10.times { |i| store.ingest(["[User] Msg#{i}\n"]) }

      # Assert - Should have properly cascaded without errors
      view = store.current_view
      view.should_not eq("")
      # Should have at least Layer 1
      view.should contain("=== Memory Layer 1 ===")

      # Cleanup
      File.delete(file_path)
    end
  end

  describe "#current_view" do
    it "returns empty string when no layers have content" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Act
      view = store.current_view

      # Assert
      view.should eq("")

      # Cleanup
      File.delete(file_path)
    end

    it "returns Layer 0 content with header" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)
      store.ingest(["[User] Test\n"])

      # Act
      view = store.current_view

      # Assert
      view.should contain("=== Memory Layer 0 ===")
      view.should contain("Summary of 1 messages")

      # Cleanup
      File.delete(file_path)
    end

    it "returns layers in reverse order (highest layer first)" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 1,
        squishifier: squishifier
      )

      # Create multiple layers
      9.times { |i| store.ingest(["[User] M#{i}\n"]) }

      # Act
      view = store.current_view

      # Assert - Layer 2 should appear before Layer 1, which appears before Layer 0
      layer2_pos = view.index("=== Memory Layer 2 ===")
      layer1_pos = view.index("=== Memory Layer 1 ===")
      layer0_pos = view.index("=== Memory Layer 0 ===")

      layer2_pos.should_not be_nil
      layer1_pos.should_not be_nil
      layer0_pos.should_not be_nil

      layer2_pos.not_nil!.should be < layer1_pos.not_nil!
      layer1_pos.not_nil!.should be < layer0_pos.not_nil!

      # Cleanup
      File.delete(file_path)
    end

    it "includes all messages from each layer" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)

      # Add multiple messages to Layer 0
      store.ingest(["[User] First\n"])
      store.ingest(["[User] Second\n"])
      store.ingest(["[User] Third\n"])

      # Act
      view = store.current_view

      # Assert - All 3 summaries should be present
      view.should contain("First")
      view.should contain("Second")
      view.should contain("Third")

      # Cleanup
      File.delete(file_path)
    end

    it "includes proper spacing between layers" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 1,
        squishifier: squishifier
      )

      # Create 2 layers
      6.times { |i| store.ingest(["[User] Msg#{i}\n"]) }

      # Act
      view = store.current_view

      # Assert - Should have newlines for readability
      view.should contain("===")
      # Each layer header should be on its own line
      view.lines.any? { |line| line.includes?("=== Memory Layer") }.should be_true

      # Cleanup
      File.delete(file_path)
    end
  end

  describe "JSON persistence" do
    it "saves correct JSON structure" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)
      store.ingest(["[User] Test\n"])

      # Act - Read the JSON file directly
      json_content = File.read(file_path)
      data = JSON.parse(json_content)

      # Assert - Should have expected structure
      data["ingest_pending"].should be_a(JSON::Any)
      data["layers"].should be_a(JSON::Any)
      data["layers"].as_a.size.should be > 0

      # Cleanup
      File.delete(file_path)
    end

    it "loads and saves data correctly across multiple instances" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Act - Create store, add data, close
      store1 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)
      store1.ingest(["[User] Persistent message\n"])
      view1 = store1.current_view

      # Create new instance with same file
      store2 = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 4, squishifier)
      view2 = store2.current_view

      # Assert - Views should match
      view1.should eq(view2)
      view2.should contain("Persistent message")

      # Cleanup
      File.delete(file_path)
    end

    it "preserves layer structure across save/load cycles" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier

      # Create multi-layer structure
      store1 = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 1,
        squishifier: squishifier
      )
      9.times { |i| store1.ingest(["[User] Message #{i}\n"]) }

      # Act - Load in new instance
      store2 = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 3,
        layer_target: 1,
        squishifier: squishifier
      )

      # Assert - Should have same structure
      store1.current_view.should eq(store2.current_view)
      store2.current_view.should contain("=== Memory Layer 2 ===")

      # Cleanup
      File.delete(file_path)
    end
  end

  describe "integration: full memory lifecycle" do
    it "handles realistic conversation flow with cascading consolidation" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 5,
        layer_target: 2,
        squishifier: squishifier
      )

      # Act - Simulate conversation over time
      # First batch of messages (fills Layer 0 to capacity)
      store.ingest(["[User] Hello\n", "[Bot] Hi there!\n"])
      store.ingest(["[User] How are you?\n", "[Bot] I'm well!\n"])
      store.ingest(["[User] What's the weather?\n", "[Bot] Sunny today.\n"])
      store.ingest(["[User] Thanks!\n", "[Bot] You're welcome.\n"])
      store.ingest(["[User] Goodbye\n", "[Bot] See you!\n"]) # Triggers consolidation

      # Second batch (refills Layer 0)
      store.ingest(["[User] Back again\n", "[Bot] Welcome back!\n"])
      store.ingest(["[User] New topic\n", "[Bot] Sure!\n"])
      store.ingest(["[User] Question\n", "[Bot] Answer\n"])
      store.ingest(["[User] Another\n", "[Bot] Response\n"])
      store.ingest(["[User] Last\n", "[Bot] Final\n"]) # Triggers another consolidation

      # Assert - Should have properly structured memory
      view = store.current_view

      # Should have Layer 1 with consolidated older messages
      view.should contain("=== Memory Layer 1 ===")

      # Layer 0 should have most recent messages
      view.should contain("=== Memory Layer 0 ===")
      view.should contain("Last")
      view.should contain("Final")

      # Verify persistence
      store2 = Mantle::JSONLayeredMemoryStore.new(file_path, 5, 2, squishifier)
      store2.current_view.should eq(view)

      # Cleanup
      File.delete(file_path)
    end

    it "handles extreme cascading with many layers" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      store = Mantle::JSONLayeredMemoryStore.new(
        memory_file: file_path,
        layer_capacity: 6,
        layer_target: 4,
        squishifier: squishifier
      )

      # Act - Add many messages to force deep cascading
      # With capacity=6, target=4, ingest_step_size=2
      # Need more ingests to create deep layers
      50.times { |i| store.ingest(["[User] Msg#{i}\n"]) }

      # Assert - Should have created multiple layers without crashing
      view = store.current_view
      view.should_not eq("")
      view.should contain("=== Memory Layer 0 ===")
      # Should have deep layers (at least 2 or 3)
      (view.includes?("=== Memory Layer 2 ===") || view.includes?("=== Memory Layer 3 ===")).should be_true

      # Cleanup
      File.delete(file_path)
    end

    it "integrates with ContextManager consolidation flow" do
      # Arrange
      file_path = temp_file_path
      squishifier = make_deterministic_squishifier
      memory_store = Mantle::JSONLayeredMemoryStore.new(file_path, 5, 2, squishifier)

      # Simulate what ContextManager does: passes pruned messages
      pruned_from_context = [
        "[User] Hello\n",
        "[Bot] Hi\n",
        "[User] How are you?\n",
        "[Bot] Good!\n",
      ]

      # Act - Ingest as ContextManager would
      memory_store.ingest(pruned_from_context)

      # Assert - Should create one summary in Layer 0
      view = memory_store.current_view
      view.should contain("=== Memory Layer 0 ===")
      view.should contain("Summary of 4 messages")
      view.should contain("[User] Hello")
      view.should contain("[Bot] Good!")

      # Cleanup
      File.delete(file_path)
    end
  end
end
