require "../spec_helper"
require "./mock_server_helper"

describe "Integration: LLM Mock Replay Server" do
  before_all do
    LlmMockHelper.start
  end

  it "replays standard text response for a fixture hit" do
    model_config = Mantle::Clients::ModelConfig.new(
      model_name: "gemma4:26b",
      stream: false,
      temperature: 0.6,
      top_p: 0.7,
      max_tokens: 700,
      api_url: "http://127.0.0.1:#{MOCK_PORT}/api/chat"
    )
    client = Mantle::Clients::LlamaClient.new(model_config)

    # Load prompt from line 1 of llm_calls.jsonl
    line = File.read_lines(FIXTURE_PATH)[0]
    parsed = JSON.parse(line)
    prompt_json = parsed["prompt"].to_json
    messages = Array(Mantle::Message).from_json(prompt_json)

    response = client.execute(messages)

    response.should be_a(Mantle::Clients::Response)
    response.content.should_not be_nil
    response.content.not_nil!.should contain("gondola")
    response.tool_calls.should be_nil
  end

  it "replays tool call response for a fixture hit with tool calls" do
    model_config = Mantle::Clients::ModelConfig.new(
      model_name: "gemma4:26b",
      stream: false,
      temperature: 0.6,
      top_p: 0.7,
      max_tokens: 700,
      api_url: "http://127.0.0.1:#{MOCK_PORT}/api/chat"
    )
    client = Mantle::Clients::LlamaClient.new(model_config)

    # Load prompt from line 2 of llm_calls.jsonl (write_file tool call)
    line = File.read_lines(FIXTURE_PATH)[1]
    parsed = JSON.parse(line)
    prompt_json = parsed["prompt"].to_json
    messages = Array(Mantle::Message).from_json(prompt_json)

    response = client.execute(messages)

    response.should be_a(Mantle::Clients::Response)
    response.tool_calls.should_not be_nil
    tool_calls = response.tool_calls.not_nil!
    tool_calls.size.should eq(1)
    tool_calls[0].function.name.should eq("write_file")
    tool_calls[0].function.arguments.should contain("GONDOLA to GONDOLA.txt")
  end

  it "replays text response following tool execution" do
    model_config = Mantle::Clients::ModelConfig.new(
      model_name: "gemma4:26b",
      stream: false,
      temperature: 0.6,
      top_p: 0.7,
      max_tokens: 700,
      api_url: "http://127.0.0.1:#{MOCK_PORT}/api/chat"
    )
    client = Mantle::Clients::LlamaClient.new(model_config)

    # Load prompt from line 3 of llm_calls.jsonl
    line = File.read_lines(FIXTURE_PATH)[2]
    parsed = JSON.parse(line)
    prompt_json = parsed["prompt"].to_json
    messages = Array(Mantle::Message).from_json(prompt_json)

    response = client.execute(messages)

    response.should be_a(Mantle::Clients::Response)
    response.content.should_not be_nil
    response.content.not_nil!.should contain("tucked away in `GONDOLA to GONDOLA.txt`")
  end

  it "returns HTTP 404 error when requesting an unrecorded prompt" do
    model_config = Mantle::Clients::ModelConfig.new(
      model_name: "gemma4:26b",
      stream: false,
      temperature: 0.6,
      top_p: 0.7,
      max_tokens: 700,
      api_url: "http://127.0.0.1:#{MOCK_PORT}/api/chat"
    )
    client = Mantle::Clients::LlamaClient.new(model_config)

    unknown_messages = [
      Mantle::Message.new("system", "System prompt"),
      Mantle::Message.new("user", "This prompt definitely does not exist in fixtures #{Random.rand(100000)}")
    ]

    expect_raises(Exception, /404/) do
      client.execute(unknown_messages)
    end
  end

  it "supports streaming response parsing for fixture hits" do
    model_config = Mantle::Clients::ModelConfig.new(
      model_name: "gemma4:26b",
      stream: true,
      temperature: 0.6,
      top_p: 0.7,
      max_tokens: 700,
      api_url: "http://127.0.0.1:#{MOCK_PORT}/api/chat"
    )
    client = Mantle::Clients::LlamaClient.new(model_config)

    line = File.read_lines(FIXTURE_PATH)[0]
    parsed = JSON.parse(line)
    prompt_json = parsed["prompt"].to_json
    messages = Array(Mantle::Message).from_json(prompt_json)

    received_chunks = [] of String
    response = client.execute(messages) do |chunk|
      received_chunks << chunk
    end

    response.should be_a(Mantle::Clients::Response)
    response.content.should_not be_nil
    received_chunks.should_not be_empty
    received_chunks.join.should eq(response.content)
  end
end
