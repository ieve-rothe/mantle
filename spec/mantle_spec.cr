# spec/mantle_spec.cr
require "./spec_helper"

describe Mantle do

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
