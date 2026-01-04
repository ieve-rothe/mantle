# spec/mantle_spec.cr
require "./spec_helper"

# Helper method to create test fixtures
def create_test_flow
  store = DummyContextStore.new
  model_config = Mantle::ModelConfig.new(
    "test-model",                         # model_name
    false,                                # stream
    0.6,                                  # temperature
    0.7,                                  # top_p
    700,                                  # max_tokens
    "http://localhost:11434/api/generate" # api_url
  )
  logger = DummyLogger.new("test-log-file.txt")
  client = DummyClient.new
  flow = DummyFlow.new(
    workspace: store,
    client: client,
    model_config: model_config,
    logger: logger,
    output_file: "test-output-file.txt"
  )
  {flow: flow, store: store, model_config: model_config, logger: logger, client: client}
end

describe Mantle do
  it "initializes with a context store, model config struct and output file" do
    # Arrange
    fixtures = create_test_flow
    flow = fixtures[:flow]
    store = fixtures[:store]
    model_config = fixtures[:model_config]

    # Act
    # We are testing initialize of Flow, which is in the create_test_flow helper

    # Assert
    flow.workspace.should eq(store)
    flow.model_config.should eq(model_config)
    flow.output_file.should eq("test-output-file.txt")
  end

  it "can be run, taking an input, assembling context to send to server and returns model output" do
    # Arrange
    fixtures = create_test_flow
    flow = fixtures[:flow]

    # Act
    flow.run("Test input")

    # Assert
    flow.context.should eq("This is a test system prompt\n" + "Test input")
    flow.output.should eq("Simulated response from model")
  end

  it "logs context sent to model and response received from model when running a flow" do
    # Arrange
    fixtures = create_test_flow
    flow = fixtures[:flow]
    logger = fixtures[:logger]

    # Act
    flow.run("Test input")

    # Assert
    logger.last_message.should eq("\n" + "Model Response\n" + "Simulated response from model")
  end
end
