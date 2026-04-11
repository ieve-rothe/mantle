# spec/client_spec.cr
require "./spec_helper"
require "http/server"
require "json"
require "../src/mantle/tools"

describe "Mantle Response Types" do
  describe "ToolCall" do
    it "deserializes from JSON correctly with string arguments (OpenAI format)" do
      json = %({"id":"call_123","type":"function","function":{"name":"read_file","arguments":"{\\"file_path\\":\\"test.txt\\"}"}})
      tool_call = Mantle::ToolCall.from_json(json)

      tool_call.id.should eq("call_123")
      tool_call.type.should eq("function")
      tool_call.function.name.should eq("read_file")
      tool_call.function.arguments.should eq(%({"file_path":"test.txt"}))
    end

    it "deserializes from JSON correctly with object arguments (Ollama format)" do
      json = %({"id":"call_456","type":"function","function":{"name":"list_directory","arguments":{"path":"."}}})
      tool_call = Mantle::ToolCall.from_json(json)

      tool_call.id.should eq("call_456")
      tool_call.type.should eq("function")
      tool_call.function.name.should eq("list_directory")
      # Arguments should be converted to JSON string
      tool_call.function.arguments.should eq(%({"path":"."}))
    end

    it "deserializes from JSON correctly with nested object arguments" do
      json = %({"id":"call_789","type":"function","function":{"name":"complex_tool","arguments":{"config":{"enabled":true,"value":42},"name":"test"}}})
      tool_call = Mantle::ToolCall.from_json(json)

      tool_call.id.should eq("call_789")
      tool_call.type.should eq("function")
      tool_call.function.name.should eq("complex_tool")
      # Arguments should be converted to JSON string, preserving structure
      parsed_args = JSON.parse(tool_call.function.arguments)
      parsed_args["name"].as_s.should eq("test")
      parsed_args["config"]["enabled"].as_bool.should eq(true)
      parsed_args["config"]["value"].as_i.should eq(42)
    end

    it "deserializes from JSON correctly without type field (defaults to 'function')" do
      json = %({"id":"call_999","function":{"name":"test_tool","arguments":{"param":"value"}}})
      tool_call = Mantle::ToolCall.from_json(json)

      tool_call.id.should eq("call_999")
      tool_call.type.should eq("function")  # Should default to "function"
      tool_call.function.name.should eq("test_tool")
      tool_call.function.arguments.should eq(%({"param":"value"}))
    end

    it "serializes to JSON correctly" do
      tool_call = Mantle::ToolCall.new(
        id: "call_456",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "list_directory",
          arguments: %({"directory_path":"."})
        )
      )

      json = tool_call.to_json
      json.should contain("call_456")
      json.should contain("list_directory")
    end
  end

  describe "Response" do
    it "can be created with only content" do
      response = Mantle::Response.new(
        content: "Hello, world!",
        tool_calls: nil
      )

      response.content.should eq("Hello, world!")
      response.tool_calls.should be_nil
    end

    it "can be created with only tool_calls" do
      tool_call = Mantle::ToolCall.new(
        id: "call_1",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "test_tool",
          arguments: "{}"
        )
      )
      response = Mantle::Response.new(
        content: nil,
        tool_calls: [tool_call]
      )

      response.content.should be_nil
      response.tool_calls.should_not be_nil
      response.tool_calls.not_nil!.size.should eq(1)
    end

    it "can be created with both content and tool_calls" do
      tool_call = Mantle::ToolCall.new(
        id: "call_1",
        type: "function",
        function: Mantle::ToolCallFunction.new(
          name: "test_tool",
          arguments: "{}"
        )
      )
      response = Mantle::Response.new(
        content: "Calling tool...",
        tool_calls: [tool_call]
      )

      response.content.should eq("Calling tool...")
      response.tool_calls.should_not be_nil
    end

    it "deserializes from JSON correctly - content only" do
      json = %({"content":"Test response"})
      response = Mantle::Response.from_json(json)

      response.content.should eq("Test response")
      response.tool_calls.should be_nil
    end

    it "deserializes from JSON correctly - with tool_calls" do
      json = %({"content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"test","arguments":"{}"}}]})
      response = Mantle::Response.from_json(json)

      response.content.should be_nil
      response.tool_calls.should_not be_nil
      response.tool_calls.not_nil!.size.should eq(1)
    end
  end
end

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
    parsed_request["keep_alive"].should eq("10m")
    parsed_request["options"]["temperature"].should eq(0.6)
    parsed_request["options"]["top_p"].should eq(0.7)
    parsed_request["options"]["num_predict"].should eq(700)

    # Check response parsing
    client_response.should be_a(Mantle::Response)
    client_response.content.should eq("The sky is blue because it is the color of the sky.")
    client_response.tool_calls.should be_nil

    # Cleanup
    server.close
  end

  it "includes tools array in request when tools are provided" do
    # Arrange
    model_config = Mantle::ModelConfig.new(
      "test-model", false, 0.6, 0.7, 700, "http://localhost:43001/"
    )
    client = Mantle::LlamaClient.new(model_config)

    # Define a test tool
    test_tool = Mantle::Tool.new(
      function: Mantle::FunctionDefinition.new(
        name: "read_file",
        description: "Read a file",
        parameters: Mantle::ParametersSchema.new(
          properties: {"file_path" => Mantle::PropertyDefinition.new("string", "File path")},
          required: ["file_path"]
        )
      )
    )

    # Mock response
    api_response = {
      "model": "test-model",
      "message": {
        "role": "assistant",
        "content": "Let me read that file for you.",
      },
      "done": true,
    }.to_json

    received_request_body : String? = nil
    server = HTTP::Server.new do |context|
      received_request_body = context.request.body.try(&.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print api_response
    end
    address = server.bind_tcp 43001

    spawn { server.listen }

    test_messages = [{"role" => "user", "content" => "Read test.txt"}]

    # Act
    client.execute(test_messages, tools: [test_tool])

    # Assert
    received_request_body.should_not be_nil
    parsed_request = JSON.parse(received_request_body.not_nil!)

    # Check that tools array is in the request
    parsed_request["tools"]?.should_not be_nil
    tools_array = parsed_request["tools"].as_a
    tools_array.size.should eq(1)
    tools_array[0]["type"].should eq("function")
    tools_array[0]["function"]["name"].should eq("read_file")

    # Check keep_alive
    parsed_request["keep_alive"].should eq("10m")

    # Cleanup
    server.close
  end

  it "parses tool_calls from API response" do
    # Arrange
    model_config = Mantle::ModelConfig.new(
      "test-model", false, 0.6, 0.7, 700, "http://localhost:43002/"
    )
    client = Mantle::LlamaClient.new(model_config)

    # Mock response with tool_calls
    api_response = {
      "model": "test-model",
      "message": {
        "role": "assistant",
        "content": nil,
        "tool_calls": [
          {
            "id": "call_123",
            "type": "function",
            "function": {
              "name": "read_file",
              "arguments": %({"file_path":"test.txt"})
            }
          }
        ]
      },
      "done": true,
    }.to_json

    server = HTTP::Server.new do |context|
      context.response.content_type = "application/json"
      context.response.print api_response
    end
    address = server.bind_tcp 43002

    spawn { server.listen }

    test_messages = [{"role" => "user", "content" => "Read test.txt"}]

    # Act
    response = client.execute(test_messages)

    # Assert
    response.content.should be_nil
    response.tool_calls.should_not be_nil
    response.tool_calls.not_nil!.size.should eq(1)
    response.tool_calls.not_nil![0].id.should eq("call_123")
    response.tool_calls.not_nil![0].function.name.should eq("read_file")

    # Cleanup
    server.close
  end

  it "handles response with both content and tool_calls" do
    # Arrange
    model_config = Mantle::ModelConfig.new(
      "test-model", false, 0.6, 0.7, 700, "http://localhost:43003/"
    )
    client = Mantle::LlamaClient.new(model_config)

    # Mock response with both
    api_response = {
      "model": "test-model",
      "message": {
        "role": "assistant",
        "content": "I'll read that file for you.",
        "tool_calls": [
          {
            "id": "call_456",
            "type": "function",
            "function": {
              "name": "read_file",
              "arguments": %({"file_path":"test.txt"})
            }
          }
        ]
      },
      "done": true,
    }.to_json

    server = HTTP::Server.new do |context|
      context.response.content_type = "application/json"
      context.response.print api_response
    end
    address = server.bind_tcp 43003

    spawn { server.listen }

    test_messages = [{"role" => "user", "content" => "Read test.txt"}]

    # Act
    response = client.execute(test_messages)

    # Assert
    response.content.should eq("I'll read that file for you.")
    response.tool_calls.should_not be_nil
    response.tool_calls.not_nil!.size.should eq(1)

    # Cleanup
    server.close
  end

  it "includes custom keep_alive value when provided" do
    model_config = Mantle::ModelConfig.new(
      "test-model", false, 0.6, 0.7, 700, "http://localhost:43004/", keep_alive: "5m"
    )
    client = Mantle::LlamaClient.new(model_config)

    api_response = {
      "model": "test-model",
      "message": {
        "role": "assistant",
        "content": "Keep alive test",
      },
      "done": true,
    }.to_json

    received_request_body : String? = nil
    server = HTTP::Server.new do |context|
      received_request_body = context.request.body.try(&.gets_to_end)
      context.response.content_type = "application/json"
      context.response.print api_response
    end
    address = server.bind_tcp 43004

    spawn { server.listen }

    test_messages = [{"role" => "user", "content" => "Test"}]

    # Act
    client.execute(test_messages)

    # Assert
    received_request_body.should_not be_nil
    parsed_request = JSON.parse(received_request_body.not_nil!)

    parsed_request["keep_alive"].should eq("5m")

    # Cleanup
    server.close
  end
end
