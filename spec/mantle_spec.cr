# spec/mantle_spec.cr
require "./spec_helper"

describe Mantle::ChatFlow do
  
  it "updates the context store with both the user input and the assistant response" do
    # Arrange
    store = DummyContextStore.new("Sys Prompt")
    client = DummyClient.new
    logger = DummyLogger.new
    flow = Mantle::ChatFlow.new(store, client, logger)

    # Act
    flow.run("Hello", ->(msg : String) { })

    # Assert
    store.chat_context.should contain("System: Initial Prompt")
    store.chat_context.should contain("[User] Hello")
    store.chat_context.should contain("[Assistant] Simulated response")
  end

  it "executes the on_response callback with the model's response" do
    # Arrange
    store = DummyContextStore.new("Sys Prompt")
    client = DummyClient.new
    logger = DummyLogger.new
    flow = Mantle::ChatFlow.new(store, client, logger)
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
    client = DummyClient.new
    logger = DummyLogger.new
    flow = Mantle::ChatFlow.new(store, client, logger)

    # Act
    flow.run("Turn 1", ->(msg : String) { })
    flow.run("Turn 2", ->(msg : String) { })

    # Assert
    store.chat_context.should contain("Turn 1")
    store.chat_context.should contain("Turn 2")
    store.chat_context.index("Turn 1").not_nil!.should be < store.chat_context.index("Turn 2").not_nil!
  end
end