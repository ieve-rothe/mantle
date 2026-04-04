# spec/mantle_spec.cr
require "./spec_helper"

describe Mantle::ChatFlow do
  it "updates the context store with both the user input and the assistant response" do
    # Arrange
    store = DummyContextStore.new("Sys Prompt")
    context_manager = DummyContextManager.new(store)
    client = DummyClient.new
    logger = DummyLogger.new
    flow = Mantle::ChatFlow.new(context_manager, client, logger)

    # Act
    flow.run("Hello", ->(msg : String) { })

    # Assert
    view = store.current_view
    view.should be_a(Array(Hash(String, String)))

    # Check system message
    system_msg = view.find { |m| m["role"] == "system" }
    system_msg.should_not be_nil
    system_msg.not_nil!["content"].should eq("Sys Prompt")

    # Check user message
    user_msg = view.find { |m| m["role"] == "user" && m["content"] == "Hello" }
    user_msg.should_not be_nil

    # Check assistant response
    assistant_msg = view.find { |m| m["role"] == "assistant" && m["content"] == "Simulated response" }
    assistant_msg.should_not be_nil
  end

  it "executes the on_response callback with the model's response" do
    # Arrange
    store = DummyContextStore.new("Sys Prompt")
    context_manager = DummyContextManager.new(store)
    client = DummyClient.new
    logger = DummyLogger.new
    flow = Mantle::ChatFlow.new(context_manager, client, logger)
    captured_message = ""
    callback = ->(msg : String) { captured_message = msg }

    # Act
    flow.run("What is 2+2?", callback)

    # Assert
    captured_message.should eq("Simulated response")
  end

  it "maintains state across multiple runs (conversational memory)" do
    # Arrange
    store = DummyContextStore.new("Sys Prompt")
    context_manager = DummyContextManager.new(store)
    client = DummyClient.new
    logger = DummyLogger.new
    flow = Mantle::ChatFlow.new(context_manager, client, logger)

    # Act
    flow.run("Turn 1", ->(msg : String) { })
    flow.run("Turn 2", ->(msg : String) { })

    # Assert
    view = store.current_view
    messages_content = view.map { |m| m["content"] }

    # Both turns should be in the view
    messages_content.should contain("Turn 1")
    messages_content.should contain("Turn 2")

    # Turn 1 should appear before Turn 2
    turn1_index = view.index { |m| m["content"] == "Turn 1" }
    turn2_index = view.index { |m| m["content"] == "Turn 2" }
    turn1_index.should_not be_nil
    turn2_index.should_not be_nil
    turn1_index.not_nil!.should be < turn2_index.not_nil!
  end
end
