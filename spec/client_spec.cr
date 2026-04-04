# spec/client_spec.cr
require "./spec_helper"
require "http/server"
require "json"

describe Mantle::Client do
  it "Correctly packs messages array and model parameters into /chat API request, sends over HTTP to API endpoint, and parses received result (no streaming)" do
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

    # Mock response from /chat endpoint
    api_response = {
      "model":      "test-model",
      "created_at": "2023-08-04T19:22:45.499127Z",
      "message": {
        "role":    "assistant",
        "content": "The sky is blue because it is the color of the sky.",
      },
      "done":                 true,
      "total_duration":       5043500667,
      "load_duration":        5025959,
      "prompt_eval_count":    26,
      "prompt_eval_duration": 325953000,
      "eval_count":           290,
      "eval_duration":        4709213000,
    }.to_json

    # Use a local variable that the closure can capture.
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

    # Prepare test messages
    test_messages = [
      {"role" => "system", "content" => "You are a helpful assistant."},
      {"role" => "user", "content" => "Why is the sky blue?"},
    ]

    # Act
    client_response = client.execute(test_messages)

    # Assert
    received_request_body.should_not be_nil
    parsed_request = JSON.parse(received_request_body.not_nil!)

    # Check messages array
    parsed_request["messages"].should_not be_nil
    messages = parsed_request["messages"].as_a
    messages.size.should eq(2)
    messages[0].as_h["role"].as_s.should eq("system")
    messages[0].as_h["content"].as_s.should eq("You are a helpful assistant.")
    messages[1].as_h["role"].as_s.should eq("user")
    messages[1].as_h["content"].as_s.should eq("Why is the sky blue?")

    # Check model config
    parsed_request["model"].should eq("test-model")
    parsed_request["options"]["temperature"].should eq(0.6)
    parsed_request["options"]["top_p"].should eq(0.7)
    parsed_request["options"]["num_predict"].should eq(700)

    # Check response parsing
    client_response.should eq("The sky is blue because it is the color of the sky.")

    # Cleanup
    server.close
  end
end
