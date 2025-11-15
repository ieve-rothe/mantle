# spec/mantle_spec.cr
require "./spec_helper"

describe Mantle do
  it "initializes with a context store, model config struct and output file" do
    # Arrange
    store = DummyContextStore.new
    model_config = Mantle::ModelConfig.new(
      "test-model",                         # model_name
      false,                                # stream
      0.6,                                  # temperature
      0.7,                                  # top_p
      700,                                  # max_tokens
      "http://localhost:11434/api/generate" # api_url
    )
    logger = DummyLogger.new
    client = DummyClient.new

    # Act
    flow = DummyFlow.new(
      workspace: store,
      client: client,
      model_config: model_config,
      logger: logger,
      output_file: "test-output-file.txt"
    )

    # Assert
    flow.workspace.should eq(store)
    flow.model_config.should eq(model_config)
    flow.output_file.should eq("test-output-file.txt")
  end

  it "can be run, taking an input, assembling context to send to server and returns model output" do
    # Arrange
    store = DummyContextStore.new
    model_config = Mantle::ModelConfig.new(
      "test-model",                         # model_name
      false,                                # stream
      0.6,                                  # temperature
      0.7,                                  # top_p
      700,                                  # max_tokens
      "http://localhost:11434/api/generate" # api_url
    )
    client = DummyClient.new
    logger = DummyLogger.new
    flow = DummyFlow.new(
      workspace: store,
      client: client,
      model_config: model_config,
      logger: logger,
      output_file: "test-output-file.txt"
    )

    # Act
    flow.run("Test input")

    # Assert
    flow.context.should eq("This is a test system prompt\n" + "Test input")
    flow.output.should eq("Simulated response from model")
  end

  it "logs context sent to model and response received from model when running a flow" do
    # Arrange
    store = DummyContextStore.new
    model_config = Mantle::ModelConfig.new(
      "test-model",                         # model_name
      false,                                # stream
      0.6,                                  # temperature
      0.7,                                  # top_p
      700,                                  # max_tokens
      "http://localhost:11434/api/generate" # api_url
    )
    client = DummyClient.new
    logger = DummyLogger.new
    flow = DummyFlow.new(
      workspace: store,
      client: client,
      model_config: model_config,
      logger: logger,
      output_file: "test-output-file.txt"
    )

    # Act
    flow.run("Test input")

    # Asset
    logger.last_message.should eq("Model Response\n" + "Simulated response from model")
  end
end
