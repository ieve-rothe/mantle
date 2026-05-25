# spec/context_manager_spec.cr
require "./spec_helper"

# Test-specific context store that tracks messages and supports pruning
class TrackingContextStore < Mantle::ContextStore
  property system_prompt : String
  property messages : Array(Hash(String, String))
  property add_message_calls : Array({String, String})

  def initialize(@system_prompt : String)
    super(system_prompt)
    @messages = [] of Hash(String, String)
    @add_message_calls = [] of {String, String}
  end

  def current_num_tokens : Int32
    current_view.sum { |msg| msg["content"].size // 4 }
  end

  def current_view : Array(Hash(String, String))
    result = [] of Hash(String, String)
    result << {"role" => "system", "content" => @system_prompt} unless @system_prompt.empty?
    result.concat(@messages)
    result
  end

  def add_message(label : String, message : String)
    @add_message_calls << {label, message}
    role = normalize_role(label)
    @messages << {"role" => role, "content" => message}
    @current_num_messages = @messages.size
  end

  def prune(num : Int32) : Array(Hash(String, String))
    num_to_prune = Math.min(num, @messages.size)
    pruned = @messages.shift(num_to_prune)
    @current_num_messages = @messages.size
    pruned
  end

def prune_to_tokens(target_tokens : Int32) : Array(Hash(String, String))
  pruned_messages = [] of Hash(String, String)
  while current_num_tokens > target_tokens && !@messages.empty?
    if @messages.first["role"] == "system" && @messages.size > 1
      system_msg = @messages.shift
      pruned_messages << @messages.shift
      @messages.unshift(system_msg)
    else
      pruned_messages << @messages.shift
    end
  end
  @current_num_messages = @messages.size
  return pruned_messages
end

def clear

    @messages.clear
    @current_num_messages = 0
  end
end

# Test-specific memory store that tracks ingestion calls
class TrackingMemoryStore < Mantle::JSONLayeredMemoryStore
  property ingested_messages : Array(Array(String))
  property layers : Array(Array(String))

  def initialize
    # Initialize parent class properties with dummy test values
    @memory_file = "/tmp/test_memory_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.json"
    @layer_token_capacity = 100
    @layer_token_target = 50
    @squishifier = ->(messages : Array(String)) : String { "" }
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

    it "uses default values for token_target and token_hardmax if not provided" do
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
      manager.token_target.should be_a(Int32)
      manager.token_hardmax.should be_a(Int32)
    end

    it "accepts custom token_target and token_hardmax values" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new

      # Act
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        token_target: 50,
        token_hardmax: 100
      )

      # Assert
      manager.token_target.should eq(50)
      manager.token_hardmax.should eq(100)
    end
  end

  describe "#current_view" do
    it "returns message array with system prompt (including memory) and conversation messages" do
      # Arrange
      context_store = TrackingContextStore.new("System Prompt")
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
      view.should be_a(Array(Hash(String, String)))
      view.size.should eq(4)  # base system + memory system + 2 conversation messages

      # Base system message
      view[0]["role"].should eq("system")
      view[0]["content"].should eq("System Prompt")

      # Memory as separate system message
      view[1]["role"].should eq("system")
      view[1]["content"].should eq("[Memory Layer 0] Previous conversation summary\n")

      # Conversation messages
      view[2]["role"].should eq("user")
      view[2]["content"].should eq("Hello")
      view[3]["role"].should eq("assistant")
      view[3]["content"].should eq("Hi there")
    end
  end

  describe "#handle_user_message" do
    it "adds user message to context store with normalized 'User' label" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "Alice", "Bot")

      # Act
      manager.handle_user_message("Hello world")

      # Assert
      context_store.add_message_calls.size.should eq(1)
      context_store.add_message_calls[0].should eq({"User", "Hello world"})

      # Check that message was added with correct role and content
      view = context_store.current_view
      user_message = view.find { |msg| msg["content"] == "Hello world" }
      user_message.should_not be_nil
      user_message.not_nil!["role"].should eq("user")
    end

    it "does not trigger consolidate_memory even when exceeding token_hardmax" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        token_target: 50,
        token_hardmax: 100
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
    it "adds bot message to context store with normalized 'Assistant' label" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "ChatBot")

      # Act
      manager.handle_bot_message("How can I help?")

      # Assert
      context_store.add_message_calls.size.should eq(1)
      context_store.add_message_calls[0].should eq({"Assistant", "How can I help?"})

      view = context_store.current_view
      bot_message = view.find { |msg| msg["content"] == "How can I help?" }
      bot_message.should_not be_nil
      bot_message.not_nil!["role"].should eq("assistant")
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

      view = context_store.current_view
      first_msg = view.find { |msg| msg["content"] == "First response" }
      second_msg = view.find { |msg| msg["content"] == "Second response" }

      first_msg.should_not be_nil
      first_msg.not_nil!["role"].should eq("assistant")
      second_msg.should_not be_nil
      second_msg.not_nil!["role"].should eq("assistant")
    end

    it "does not trigger consolidate_memory when below token_hardmax" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        token_target: 50,
        token_hardmax: 100
      )

      # Act - Add 5 messages (below hardmax of 10)
      5.times do |i|
        manager.handle_bot_message("Response #{i}")
      end

      # Assert - Memory store should not have been called
      memory_store.ingested_messages.size.should eq(0)
      context_store.messages.size.should eq(5)
    end

    it "triggers consolidate_memory when reaching token_hardmax" do
  context_store = TrackingContextStore.new("System")
  memory_store = TrackingMemoryStore.new
  manager = Mantle::ContextManager.new(
    context_store: context_store,
    memory_store: memory_store,
    user_name: "User",
    bot_name: "Bot",
    token_target: 20,
    token_hardmax: 40
  )

  20.times do |i|
    manager.handle_bot_message("Response  ")
  end

  memory_store.ingested_messages.size.should be > 0
  context_store.current_num_tokens.should be <= manager.token_target
end

it "triggers consolidate_memory when exceeding token_hardmax" do
  context_store = TrackingContextStore.new("System")
  memory_store = TrackingMemoryStore.new
  manager = Mantle::ContextManager.new(
    context_store: context_store,
    memory_store: memory_store,
    user_name: "User",
    bot_name: "Bot",
    token_target: 20,
    token_hardmax: 30
  )

  15.times do |i|
    manager.handle_bot_message("Response  ")
  end

  memory_store.ingested_messages.size.should be > 0
  context_store.current_num_tokens.should be <= manager.token_target
end


    end
  end

  describe "#consolidate_memory" do
  it "prunes oldest messages to reach token_target" do
    context_store = TrackingContextStore.new("System")
    memory_store = TrackingMemoryStore.new
    manager = Mantle::ContextManager.new(
      context_store: context_store,
      memory_store: memory_store,
      user_name: "User",
      bot_name: "Bot",
      token_target: 20,
      token_hardmax: 40
    )

    20.times do |i|
      manager.handle_bot_message("Response  ", check_consolidation: false)
    end

    manager.consolidate_memory

    context_store.current_num_tokens.should be <= manager.token_target
  end

  it "ingests pruned messages into memory_store as formatted strings" do
    context_store = TrackingContextStore.new("System")
    memory_store = TrackingMemoryStore.new
    manager = Mantle::ContextManager.new(
      context_store: context_store,
      memory_store: memory_store,
      user_name: "User",
      bot_name: "Bot",
      token_target: 20,
      token_hardmax: 40
    )

    20.times do |i|
      manager.handle_bot_message("Response  ", check_consolidation: false)
    end

    manager.consolidate_memory

    memory_store.ingested_messages.size.should eq(1)
    memory_store.ingested_messages[0].first.should contain("[Bot] Response  ")
  end

  it "leaves token_target tokens remaining in context_store" do
    context_store = TrackingContextStore.new("System")
    memory_store = TrackingMemoryStore.new
    manager = Mantle::ContextManager.new(
      context_store: context_store,
      memory_store: memory_store,
      user_name: "User",
      bot_name: "Bot",
      token_target: 20,
      token_hardmax: 40
    )

    20.times do |i|
      manager.handle_bot_message("Response  ", check_consolidation: false)
    end

    manager.consolidate_memory

    context_store.current_num_tokens.should be <= manager.token_target
  end
  end

  describe "#clear_context" do
    it "calls clear on the context store" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")
      context_store.add_message("User", "Hello")

      # Act
      manager.clear_context

      # Assert
      context_store.messages.size.should eq(0)
      context_store.current_num_messages.should eq(0)
    end
  end

  describe "integration: user and bot message flow with consolidation" do
    it "handles conversational flow with automatic memory consolidation on bot messages" do
      # Arrange
      context_store = TrackingContextStore.new("You are a helpful assistant.")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "Alice",
        bot_name: "ChatBot",
        token_target: 20,
        token_hardmax: 40
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
      # After consolidation, tokens can grow back up to (but not reaching) token_hardmax
      context_store.current_num_tokens.should be < manager.token_hardmax

      # Most recent messages should still be in context
      view = context_store.current_view
      # At token_target=5, many messages will be pruned. Let's make sure the last message is there
      last_message = view.find { |msg| msg["content"] == "Happy to help!" }
      last_message.should_not be_nil
    end
  end

  describe "#stats" do
    it "returns correctly populated stats NamedTuple" do
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new

      # Mock the layers sizes so we have something to check
      memory_store.layers = [["mock memory"], ["mock memory 2", "mock memory 3"]]

      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        token_target: 20,
        token_softmax: 30,
        token_hardmax: 40
      )

      manager.handle_user_message("Hello there")
      manager.handle_bot_message("Hi!")

      stats = manager.stats

      stats[:context_tokens].should be > 0
      stats[:context_softmax].should eq(30)
      stats[:context_hardmax].should eq(40)
      stats[:memory_layers].should eq(2)
      stats[:memory_layer_stats].size.should eq(2)

      stats[:memory_layer_stats][0][:layer].should eq(0)
      stats[:memory_layer_stats][0][:tokens].should be >= 0
      stats[:memory_layer_stats][0][:capacity].should eq(memory_store.layer_token_capacity)

      stats[:memory_layer_stats][1][:layer].should eq(1)
      stats[:memory_layer_stats][1][:tokens].should be >= 0
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("The answer is 42.")
        bot_message.not_nil!["content"].should_not contain("<think>")
        bot_message.not_nil!["content"].should_not contain("Let me analyze this")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("Answer part 1.Answer part 2.")
        bot_message.not_nil!["content"].should_not contain("<think>")
        bot_message.not_nil!["content"].should_not contain("First thought")
        bot_message.not_nil!["content"].should_not contain("Second thought")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("Here's my answer.")
        bot_message.not_nil!["content"].should_not contain("<think>")
        bot_message.not_nil!["content"].should_not contain("First point")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should contain("The answer is 42.")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("Just a normal response without any thinking tags.")
      end

      it "strips thinking tags before storing in context during consolidation" do
  context_store = TrackingContextStore.new("System")
  memory_store = TrackingMemoryStore.new
  manager = Mantle::ContextManager.new(
    context_store: context_store,
    memory_store: memory_store,
    user_name: "User",
    bot_name: "Bot",
    token_target: 20,
    token_hardmax: 40,
    strip_thinking_tags: true
  )

  20.times do |i|
    manager.handle_bot_message("<think>Thinking #{i}</think>Response  ")
  end

  memory_store.ingested_messages.size.should be > 0
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should contain("<think>My reasoning process</think>")
        bot_message.not_nil!["content"].should contain("The answer is 42.")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("<think>Analysis</think>Result")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("Answer")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("The answer is 42.")
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
        view = context_store.current_view
        bot_message = view.find { |msg| msg["role"] == "assistant" }
        bot_message.should_not be_nil
        bot_message.not_nil!["content"].should eq("")
      end
    end
  end

  describe "#current_view with ephemeral_blocks" do
    it "inserts ephemeral blocks as separate system messages after base system prompt" do
      # Arrange
      context_store = TrackingContextStore.new("Base System Prompt")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      context_store.add_message("User", "Hello")

      ephemeral_blocks = ["K-Line 1: Critical info", "Demon: Switch to dev mode"]

      # Act
      view = manager.current_view(ephemeral_blocks)

      # Assert
      view.size.should eq(4)  # base system + 2 ephemeral + 1 user message

      # Base system message comes first
      view[0]["role"].should eq("system")
      view[0]["content"].should eq("Base System Prompt")

      # Ephemeral blocks follow as separate system messages
      view[1]["role"].should eq("system")
      view[1]["content"].should eq("K-Line 1: Critical info")

      view[2]["role"].should eq("system")
      view[2]["content"].should eq("Demon: Switch to dev mode")

      # User message comes last
      view[3]["role"].should eq("user")
      view[3]["content"].should eq("Hello")
    end

    it "maintains correct order with memory and ephemeral blocks" do
      # Arrange
      context_store = TrackingContextStore.new("System Prompt")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Add memory
      memory_store.layers << ["[Memory] Previous conversation\n"]

      # Add messages
      context_store.add_message("User", "Hello")
      context_store.add_message("Bot", "Hi")

      ephemeral_blocks = ["Ephemeral instruction"]

      # Act
      view = manager.current_view(ephemeral_blocks)

      # Assert - Order: base system → ephemeral → memory → context
      view[0]["role"].should eq("system")
      view[0]["content"].should eq("System Prompt")

      view[1]["role"].should eq("system")
      view[1]["content"].should eq("Ephemeral instruction")

      view[2]["role"].should eq("system")
      view[2]["content"].should eq("[Memory] Previous conversation\n")

      view[3]["role"].should eq("user")
      view[3]["content"].should eq("Hello")

      view[4]["role"].should eq("assistant")
      view[4]["content"].should eq("Hi")
    end

    it "does not persist ephemeral blocks in context store" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      context_store.add_message("User", "Test message")

      ephemeral_blocks = ["Ephemeral 1", "Ephemeral 2"]

      # Act
      view_with_ephemeral = manager.current_view(ephemeral_blocks)
      view_without_ephemeral = manager.current_view

      # Assert - ephemeral blocks appear in first call
      view_with_ephemeral.size.should eq(4)  # system + 2 ephemeral + 1 user

      # But not in second call (not persisted)
      view_without_ephemeral.size.should eq(2)  # system + 1 user
      view_without_ephemeral[0]["role"].should eq("system")
      view_without_ephemeral[0]["content"].should eq("System")
      view_without_ephemeral[1]["role"].should eq("user")
      view_without_ephemeral[1]["content"].should eq("Test message")
    end

    it "handles empty ephemeral_blocks array gracefully" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      context_store.add_message("User", "Hello")

      # Act
      view = manager.current_view([] of String)

      # Assert
      view.size.should eq(2)  # system + 1 user
      view[0]["role"].should eq("system")
      view[1]["role"].should eq("user")
    end

    it "applies ephemeral blocks only for single call without affecting context" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Act - Call with ephemeral blocks
      view1 = manager.current_view(["Ephemeral instruction"])

      # Add a new message
      context_store.add_message("User", "New message")

      # Call again without ephemeral blocks
      view2 = manager.current_view

      # Assert - First call had ephemeral block
      view1.any? { |msg| msg["content"] == "Ephemeral instruction" }.should be_true

      # Second call does not have ephemeral block
      view2.any? { |msg| msg["content"] == "Ephemeral instruction" }.should be_false

      # Context store was not affected
      context_store.messages.none? { |msg| msg["content"] == "Ephemeral instruction" }.should be_true
    end
  end

  describe "#handle_user_message with invisible_append" do
    it "applies invisible append to user message in current_view but not in context store" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Act
      manager.handle_user_message("Let's fix the bug.", invisible_append: "\n\n[System: Dev intent detected. Switch frames.]")
      view = manager.current_view

      # Assert - invisible append appears in current_view
      user_message = view.find { |msg| msg["role"] == "user" }
      user_message.should_not be_nil
      user_message.not_nil!["content"].should eq("Let's fix the bug.\n\n[System: Dev intent detected. Switch frames.]")

      # But not in context store
      context_store.messages.last["content"].should eq("Let's fix the bug.")
    end

    it "applies invisible append exactly once and clears it" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Act
      manager.handle_user_message("Test message", invisible_append: " [APPEND]")
      view1 = manager.current_view
      view2 = manager.current_view

      # Assert - First call has the append
      user_msg1 = view1.find { |msg| msg["role"] == "user" }
      user_msg1.not_nil!["content"].should eq("Test message [APPEND]")

      # Second call does NOT have the append (it was cleared)
      user_msg2 = view2.find { |msg| msg["role"] == "user" }
      user_msg2.not_nil!["content"].should eq("Test message")
    end

    it "appends to the last user message when multiple user messages exist" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Add several messages
      manager.handle_user_message("First message")
      manager.handle_bot_message("Response")
      manager.handle_user_message("Second message", invisible_append: " [INVISIBLE]")

      # Act
      view = manager.current_view

      # Assert - Only the last user message gets the append
      user_messages = view.select { |msg| msg["role"] == "user" }
      user_messages.size.should eq(2)
      user_messages[0]["content"].should eq("First message")
      user_messages[1]["content"].should eq("Second message [INVISIBLE]")
    end

    it "handles nil invisible_append gracefully" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")

      # Act
      manager.handle_user_message("Normal message", invisible_append: nil)
      view = manager.current_view

      # Assert
      user_message = view.find { |msg| msg["role"] == "user" }
      user_message.not_nil!["content"].should eq("Normal message")
    end

    it "does not affect context store even after consolidation" do
      # Arrange
      context_store = TrackingContextStore.new("System")
      memory_store = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(
        context_store: context_store,
        memory_store: memory_store,
        user_name: "User",
        bot_name: "Bot",
        token_target: 20,
        token_hardmax: 40
      )

      # Act - Add message with invisible append, then trigger consolidation
      manager.handle_user_message("Test", invisible_append: " [SYSTEM INSTRUCTION]")
      view_before = manager.current_view  # This applies and clears the append
      
      # Add more messages to trigger consolidation
      10.times { manager.handle_bot_message("Response  ") }

      # Assert - The invisible append was never persisted to context
      context_store.add_message_calls.any? { |label, msg| msg.includes?("[SYSTEM INSTRUCTION]") }.should be_false

      # And it's not in memory either
      memory_store.ingested_messages.each do |batch|
        batch.any? { |msg| msg.includes?("[SYSTEM INSTRUCTION]") }.should be_false
      end
    end
  end

  describe "#flush_and_swap" do
    it "flushes pending ingestion to old memory store before swapping" do
      # Arrange
      old_context = TrackingContextStore.new("Old System")
      old_memory = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(old_context, old_memory, "User", "Bot")

      # Add messages to old stores
      manager.handle_user_message("Old message")
      manager.handle_bot_message("Old response")

      # Simulate pending ingestion
      old_memory.ingest(["Pending item 1", "Pending item 2"])

      # Create new stores
      new_context = TrackingContextStore.new("New System")
      new_memory = TrackingMemoryStore.new

      # Act
      manager.flush_and_swap(new_context, new_memory)

      # Assert - Old memory should have the ingested items
      old_memory.ingested_messages.size.should be > 0
    end

    it "successfully attaches new stores" do
      # Arrange
      old_context = TrackingContextStore.new("Old System")
      old_memory = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(old_context, old_memory, "User", "Bot")

      manager.handle_user_message("Old message")

      new_context = TrackingContextStore.new("New System")
      new_memory = TrackingMemoryStore.new

      # Act
      manager.flush_and_swap(new_context, new_memory)

      # Assert - Manager should now be using new stores
      manager.context_store.should eq(new_context)
      manager.memory_store.should eq(new_memory)
    end

    it "reflects new stores in current_view" do
      # Arrange
      old_context = TrackingContextStore.new("Old System")
      old_memory = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(old_context, old_memory, "User", "Bot")

      manager.handle_user_message("Old message")

      new_context = TrackingContextStore.new("New System")
      new_memory = TrackingMemoryStore.new
      new_context.add_message("User", "New message")
      new_memory.layers << ["New memory layer"]

      # Act
      manager.flush_and_swap(new_context, new_memory)
      view = manager.current_view

      # Assert - View should reflect new stores
      view.any? { |msg| msg["content"] == "New message" }.should be_true
      view.any? { |msg| msg["content"].includes?("New memory layer") }.should be_true
      view.any? { |msg| msg["content"] == "Old message" }.should be_false
    end

    it "clears pending invisible append during swap" do
      # Arrange
      old_context = TrackingContextStore.new("Old System")
      old_memory = TrackingMemoryStore.new
      manager = Mantle::ContextManager.new(old_context, old_memory, "User", "Bot")

      # Set up a pending invisible append
      manager.handle_user_message("Test", invisible_append: " [PENDING]")

      new_context = TrackingContextStore.new("New System")
      new_memory = TrackingMemoryStore.new
      new_context.add_message("User", "New message")

      # Act
      manager.flush_and_swap(new_context, new_memory)
      view = manager.current_view

      # Assert - Pending append should be cleared, new message should not have it
      user_msg = view.find { |msg| msg["content"].includes?("New message") }
      user_msg.should_not be_nil
      user_msg.not_nil!["content"].should eq("New message")
      user_msg.not_nil!["content"].should_not contain("[PENDING]")
    end
  end
