# spec/client_spec.cr
require "./spec_helper"
require "http/server"
require "json"

describe Mantle::Client do
  it "Correctly packs input request and model parameters into API request, sends over HTTP to API endpoint, and parses received result (no streaming)" do
    # Arrange
    model_config = Mantle::ModelConfig.new(
      "test-model",             # model_name
      false,                    # stream
      0.6,                      # temperature
      0.7,                      # top_p
      700,                      # max_tokens
      "http://localhost:43000/" # api_url
    )
    client = Mantle::LlamaClient.new(model_config)

    api_response = {
      "model":                "llama3.2",
      "created_at":           "2023-08-04T19:22:45.499127Z",
      "response":             "The sky is blue because it is the color of the sky.",
      "done":                 true,
      "context":              [1, 2, 3],
      "total_duration":       5043500667,
      "load_duration":        5025959,
      "prompt_eval_count":    26,
      "prompt_eval_duration": 325953000,
      "eval_count":           290,
      "eval_duration":        4709213000,
    }.to_json

    # Use a local variable that the closure can capture.
    # Reminder that we can't use instance variables except inside classes / modules.
    # The local variable was giving a 'read before assignment' error down on the assert line until we actually assigned it nil here. Can't just define variable and type.
    received_request_body : String? = nil
    server = HTTP::Server.new do |context|
      received_request_body = context.request.body.try(&.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print api_response
    end
    address = server.bind_tcp 43000

    # Run server in a separate fiber so it doesn't block
    spawn do
      server.listen
    end

    # Act
    client_response = client.execute("test prompt")

    # Assert
    received_request_body.should_not be_nil
    parsed_request = JSON.parse(received_request_body.not_nil!)
    parsed_request["prompt"].should eq("test prompt")
    parsed_request["model"].should eq("test-model")
    parsed_request["temperature"].should eq(0.6)
    client_response.should eq("The sky is blue because it is the color of the sky.")

    # Cleanup
    server.close
  end
end
