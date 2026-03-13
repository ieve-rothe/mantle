# spec/context_manager_spec.cr
require "./spec_helper"

# Test-specific context store that tracks messages and supports pruning
class TrackingContextStore < Mantle::ContextStore
  property system_prompt : String
  property messages : Array(String)
  property add_message_calls : Array({String, String})

  def initialize(@system_prompt : String)
    super(system_prompt)
    @messages = [] of String
    @add_message_calls = [] of {String, String}
  end

  def current_view : String
    @system_prompt + @messages.join
  end

  def add_message(label : String, message : String)
    @add_message_calls << {label, message}
    @messages << "[#{label}] #{message}\n"
    @current_num_messages = @messages.size
  end

  def prune(num : Int32) : Array(String)
    num_to_prune = Math.min(num, @messages.size)
    pruned = @messages.shift(num_to_prune)
    @current_num_messages = @messages.size
    pruned
  end
end

# Test-specific memory store that tracks ingestion calls
class TrackingMemoryStore < Mantle::JSONLayeredMemoryStore
  property ingested_messages : Array(Array(String))
  property layers : Array(Array(String))

  def initialize
    # Initialize parent class properties with dummy test values
    @memory_file = "/tmp/test_memory_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
    @layer_capacity = 10
    @layer_target = 5
    @squishifier = ->(messages : Array(String)) : String { "" }
    @ingest_step_size = (@layer_capacity - @layer_target)
    # Initialize test tracking properties
    @ingested_messages = [] of Array(String)
    @layers = [] of Array(String)
  end

  def current_view : String
    # Concatenate all layers, with each layer's strings joined together
    @layers.map_with_index do |layer, idx|
      layer.join
    end.join
  end

  def ingest(messages : Array(String))
    @ingested_messages << messages
    # Add ingested messages to Layer 0 for testing purposes
    if @layers.empty?
      @layers << messages
    else
      @layers[0] = @layers[0] + messages
    end
  end
end

describe Mantle::ContextManager do
  describe "#initialize" do
    it "accepts context_store, memory_store, user_name, and bot_name" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new

      # Act
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "Alice",
        bot_name: "ChatBot"
      )

      # Assert
      manager.context_store.should eq(context_store)
      manager.memory_store.should eq(memory_store)
      manager.user_name.should eq("Alice")
      manager.bot_name.should eq("ChatBot")
    end

    it "uses default values for msg_target and msg_hardmax if not provided" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new

      # Act
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot"
      )

      # Assert - Should have some default values set
      manager.msg_target.should be_a(Int32)
      manager.msg_hardmax.should be_a(Int32)
    end

    it "accepts custom msg_target and msg_hardmax values" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new

      # Act
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 5,
        msg_hardmax: 10
      )

      # Assert
      manager.msg_target.should eq(5)
      manager.msg_hardmax.should eq(10)
    end
  end

  describe "#current_view" do
    it "returns concatenated view from context_store and memory_store" do
      # Arrange
      context_store = TrackingContextStore.new("System Prompt\n")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Add some memory layer data
      memory_store.layers << ["[Memory Layer 0] Previous conversation summary\n"]

      # Add current context messages
      context_store.add_message("User", "Hello")
      context_store.add_message("Bot", "Hi there")

      # Act
      view = manager.current_view

      # Assert
      # Should contain both memory and context
      view.should contain("[Memory Layer 0] Previous conversation summary")
      view.should contain("[User] Hello")
      view.should contain("[Bot] Hi there")
    end
  end

  describe "#handle_user_message" do
    it "adds user message to context store with user_name label" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "Alice", "Bot")

      # Act
      manager.handle_user_message("Hello world")

      # Assert
      context_store.add_message_calls.size.should eq(1)
      context_store.add_message_calls[0].should eq({"Alice", "Hello world"})
      context_store.current_view.should contain("[Alice] Hello world")
    end

    it "does not trigger consolidate_memory even when exceeding msg_hardmax" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 5,
        msg_hardmax: 10
      )

      # Act - Add messages exceeding hardmax
      15.times do |i|
        manager.handle_user_message("Message #{i}")
      end

      # Assert - Memory store should not have been called
      # User messages should not trigger consolidation to avoid delaying user
      memory_store.ingested_messages.size.should eq(0)
      context_store.messages.size.should eq(15)
    end
  end

  describe "#handle_bot_message" do
    it "adds bot message to context store with bot_name label" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "ChatBot")

      # Act
      manager.handle_bot_message("How can I help?")

      # Assert
      context_store.add_message_calls.size.should eq(1)
      context_store.add_message_calls[0].should eq({"ChatBot", "How can I help?"})
      context_store.current_view.should contain("[ChatBot] How can I help?")
    end

    it "handles multiple bot messages in sequence" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Assistant")

      # Act
      manager.handle_bot_message("First response")
      manager.handle_bot_message("Second response")

      # Assert
      context_store.add_message_calls.size.should eq(2)
      context_store.current_view.should contain("[Assistant] First response")
      context_store.current_view.should contain("[Assistant] Second response")
    end

    it "does not trigger consolidate_memory when below msg_hardmax" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 5,
        msg_hardmax: 10
      )

      # Act - Add 5 messages (below hardmax of 10)
      5.times do |i|
        manager.handle_bot_message("Response #{i}")
      end

      # Assert - Memory store should not have been called
      memory_store.ingested_messages.size.should eq(0)
      context_store.messages.size.should eq(5)
    end

    it "triggers consolidate_memory when reaching msg_hardmax" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 5,
        msg_hardmax: 10
      )

      # Act - Add exactly msg_hardmax messages
      10.times do |i|
        manager.handle_bot_message("Response #{i}")
      end

      # Assert - Should have pruned (10 - 5 = 5) messages to memory
      memory_store.ingested_messages.size.should eq(1)
      memory_store.ingested_messages[0].size.should eq(5)
      # Should have msg_target (5) messages remaining
      context_store.messages.size.should eq(5)
    end

    it "triggers consolidate_memory when exceeding msg_hardmax" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 3,
        msg_hardmax: 8
      )

      # Act - Add 12 messages (exceeding hardmax)
      12.times do |i|
        manager.handle_bot_message("Response #{i}")
      end

      # Assert - Should have triggered consolidation at least once
      memory_store.ingested_messages.size.should be > 0
      # After consolidation, messages can grow back up to (but not reaching) msg_hardmax
      context_store.messages.size.should be < manager.msg_hardmax
    end
  end

  describe "#consolidate_memory" do
    it "prunes (msg_hardmax - msg_target) oldest messages from context_store" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 3,
        msg_hardmax: 7
      )

      # Add 7 messages
      7.times do |i|
        context_store.add_message("User", "Message #{i}")
      end

      # Act
      manager.consolidate_memory

      # Assert - Should prune 7 - 3 = 4 messages
      context_store.messages.size.should eq(3)
      # Remaining messages should be the most recent ones
      context_store.current_view.should contain("Message 4")
      context_store.current_view.should contain("Message 5")
      context_store.current_view.should contain("Message 6")
      context_store.current_view.should_not contain("Message 0")
      context_store.current_view.should_not contain("Message 1")
    end

    it "ingests pruned messages into memory_store" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 2,
        msg_hardmax: 5
      )

      # Add 5 messages
      5.times do |i|
        context_store.add_message("User", "Message #{i}")
      end

      # Act
      manager.consolidate_memory

      # Assert - Should have called ingest with 3 pruned messages
      memory_store.ingested_messages.size.should eq(1)
      memory_store.ingested_messages[0].size.should eq(3)
      memory_store.ingested_messages[0][0].should contain("Message 0")
      memory_store.ingested_messages[0][1].should contain("Message 1")
      memory_store.ingested_messages[0][2].should contain("Message 2")
    end

    it "leaves msg_target messages remaining in context_store" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        msg_target: 4,
        msg_hardmax: 10
      )

      # Add 10 messages
      10.times do |i|
        context_store.add_message("User", "Msg#{i}")
      end

      # Act
      manager.consolidate_memory

      # Assert
      context_store.messages.size.should eq(4)
    end
  end

  describe "integration: user and bot message flow with consolidation" do
    it "handles conversational flow with automatic memory consolidation on bot messages" do
      # Arrange
      context_store = TrackingContextStore.new("You are a helpful assistant.\n")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "Alice",
        bot_name: "ChatBot",
        msg_target: 4,
        msg_hardmax: 8
      )

      # Act - Simulate a conversation that exceeds hardmax
      manager.handle_user_message("Hello")
      manager.handle_bot_message("Hi Alice!")
      manager.handle_user_message("How are you?")
      manager.handle_bot_message("I'm doing well, thanks!")
      manager.handle_user_message("What's the weather?")
      manager.handle_bot_message("I don't have weather data")
      manager.handle_user_message("Can you help with code?")
      manager.handle_bot_message("Yes, I can help!")
      # This 9th message (bot message) should trigger consolidation
      manager.handle_user_message("Great!")
      manager.handle_bot_message("Happy to help!")

      # Assert
      # Should have consolidated at least once (triggered by bot message)
      memory_store.ingested_messages.size.should be > 0
      # After consolidation, messages can grow back up to (but not reaching) msg_hardmax
      context_store.messages.size.should be < manager.msg_hardmax
      # Most recent messages should still be in context
      context_store.current_view.should contain("Happy to help!")
    end
  end

  describe "#strip_thinking_tags" do
    describe "when strip_thinking_tags is enabled" do
      it "strips a single <think> block from bot message" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        manager.handle_bot_message("<think>Let me analyze this...</think>The answer is 42.")

        # Assert - thinking block should be removed
        context_store.current_view.should eq("System[Bot] The answer is 42.\n")
        context_store.current_view.should_not contain("<think>")
        context_store.current_view.should_not contain("Let me analyze this")
      end

      it "strips multiple <think> blocks from bot message" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        manager.handle_bot_message("<think>First thought</think>Answer part 1.<think>Second thought</think>Answer part 2.")

        # Assert - both thinking blocks should be removed
        context_store.current_view.should eq("System[Bot] Answer part 1.Answer part 2.\n")
        context_store.current_view.should_not contain("<think>")
        context_store.current_view.should_not contain("First thought")
        context_store.current_view.should_not contain("Second thought")
      end

      it "handles thinking blocks with newlines and complex content" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        message_with_newlines = "<think>\nLet me think step by step:\n1. First point\n2. Second point\n</think>Here's my answer."
        manager.handle_bot_message(message_with_newlines)

        # Assert
        context_store.current_view.should eq("System[Bot] Here's my answer.\n")
        context_store.current_view.should_not contain("<think>")
        context_store.current_view.should_not contain("First point")
      end

      it "handles malformed tags gracefully (unmatched opening tag)" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act - unmatched opening tag
        manager.handle_bot_message("<think>Incomplete thought... The answer is 42.")

        # Assert - should handle gracefully, keeping the original message
        context_store.current_view.should contain("The answer is 42.")
      end

      it "preserves message when no thinking tags are present" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        manager.handle_bot_message("Just a normal response without any thinking tags.")

        # Assert - message should be unchanged
        context_store.current_view.should eq("System[Bot] Just a normal response without any thinking tags.\n")
      end

      it "strips thinking tags before storing in context during consolidation" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          msg_target: 2,
          msg_hardmax: 4,
          strip_thinking_tags: true
        )

        # Act - Add messages with thinking tags that will trigger consolidation
        manager.handle_bot_message("<think>Thinking 1</think>Response 1")
        manager.handle_bot_message("<think>Thinking 2</think>Response 2")
        manager.handle_bot_message("<think>Thinking 3</think>Response 3")
        manager.handle_bot_message("<think>Thinking 4</think>Response 4")

        # Assert - Memory should have ingested messages WITHOUT thinking tags
        memory_store.ingested_messages.size.should eq(1)
        memory_store.ingested_messages[0].each do |msg|
          msg.should_not contain("<think>")
          msg.should_not contain("Thinking")
        end
      end
    end

    describe "when strip_thinking_tags is disabled (default)" do
      it "preserves thinking tags in bot messages by default" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot"
          # strip_thinking_tags not specified, should default to false
        )

        # Act
        manager.handle_bot_message("<think>My reasoning process</think>The answer is 42.")

        # Assert - thinking tags should be preserved
        context_store.current_view.should contain("<think>My reasoning process</think>")
        context_store.current_view.should contain("The answer is 42.")
      end

      it "preserves thinking tags when explicitly set to false" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: false
        )

        # Act
        manager.handle_bot_message("<think>Analysis</think>Result")

        # Assert
        context_store.current_view.should contain("<think>Analysis</think>Result")
      end
    end

    describe "edge cases" do
      it "handles empty thinking blocks" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        manager.handle_bot_message("<think></think>Answer")

        # Assert
        context_store.current_view.should eq("System[Bot] Answer\n")
      end

      it "handles thinking blocks at the end of message" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        manager.handle_bot_message("The answer is 42.<think>I should verify this</think>")

        # Assert
        context_store.current_view.should eq("System[Bot] The answer is 42.\n")
      end

      it "handles message that is only thinking tags" do
        # Arrange
        context_store = TrackingContextStore.new("System")
        memory_store = TrackingMemoryStore.new
        manager = Mantle::ContextManager.new(
          context_store: context_store,
          memory_store: memory_store,
          user_name: "User",
          bot_name: "Bot",
          strip_thinking_tags: true
        )

        # Act
        manager.handle_bot_message("<think>Only thinking, no answer</think>")

        # Assert
        context_store.current_view.should eq("System[Bot] \n")
      end
    end
  end
end
