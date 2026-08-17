# spec/clients/logging_client_spec.cr
require "../spec_helper"
require "file_utils"
require "json"

class DummyLoggingTestClient < Mantle::Clients::Client
  property should_raise : Bool = false
  property model_name : String = "dummy-model"
  property max_tokens : Int32 = 4096

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    if @should_raise
      raise Exception.new("Simulated API Error")
    end
    on_chunk.call("Hello ")
    on_chunk.call("World")
    Mantle::Clients::Response.new(
      content: "Hello World",
      tool_calls: nil,
      thinking: "Thinking hard...",
      done_reason: "stop",
      prompt_eval_count: 10,
      eval_count: 2
    )
  end
end

describe Mantle::Clients::LoggingClient do
  temp_dir = File.join(Dir.tempdir, "logging_client_spec_#{Random.rand(100000)}")

  before_each do
    Dir.mkdir_p(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end

  it "writes a valid JSONL receipt on successful execute" do
    log_file = File.join(temp_dir, "test_llm.jsonl")
    dummy = DummyLoggingTestClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    messages = [Mantle::Message.new("user", "Hi there")]

    Mantle::LogContext.with_sequence_id("seq-123") do
      resp = client.execute(messages)
      resp.content.should eq("Hello World")
    end

    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(1)

    json = JSON.parse(lines.first)
    json["id"]?.should_not be_nil
    json["sequence_id"].as_s.should eq("seq-123")
    json["model"].as_s.should eq("dummy-model")
    json["input_hash"].as_s.should_not be_empty
    json["status"].as_s.should eq("success")
    json["error_message"].raw.should be_nil
    json["raw_output"]["content"].as_s.should eq("Hello World")
    json["raw_output"]["thinking"].as_s.should eq("Thinking hard...")
    json["raw_output"]["done_reason"].as_s.should eq("stop")
    json["raw_output"]["prompt_eval_count"].as_i.should eq(10)
    json["raw_output"]["eval_count"].as_i.should eq(2)
    (json["latency_ms"].as_i >= 0).should be_true
  end

  it "logs error receipt and re-raises when client execution fails" do
    log_file = File.join(temp_dir, "test_error.jsonl")
    dummy = DummyLoggingTestClient.new
    dummy.should_raise = true
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    messages = [Mantle::Message.new("user", "Crash please")]

    expect_raises(Exception, "Simulated API Error") do
      Mantle::LogContext.with_sequence_id("seq-error") do
        client.execute(messages)
      end
    end

    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(1)

    json = JSON.parse(lines.first)
    json["sequence_id"].as_s.should eq("seq-error")
    json["status"].as_s.should eq("error")
    json["error_message"].as_s.should eq("Simulated API Error")
    json["raw_output"]["content"].raw.should be_nil
  end

  it "forwards unhandled methods to underlying client" do
    log_file = File.join(temp_dir, "test_fwd.jsonl")
    dummy = DummyLoggingTestClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    client.max_tokens.should eq(4096)
  end

  it "rescues file write errors gracefully without breaking execute" do
    log_file = "/invalid_dir_path_non_existent_12345/llm.jsonl"
    dummy = DummyLoggingTestClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    messages = [Mantle::Message.new("user", "Hello")]
    resp = client.execute(messages)
    resp.content.should eq("Hello World")
  end

  it "emits warning when log file exceeds threshold" do
    log_file = File.join(temp_dir, "test_size.jsonl")
    dummy = DummyLoggingTestClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file, size_warning_threshold_bytes: 10_i64)

    messages = [Mantle::Message.new("user", "Trigger warning")]
    client.execute(messages)

    (File.size(log_file) > 10).should be_true
  end

  it "preserves sequence_id in child fibers when spawned with context" do
    log_file = File.join(temp_dir, "test_fiber.jsonl")
    dummy = DummyLoggingTestClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)
    messages = [Mantle::Message.new("user", "Fiber test")]

    channel = Channel(Nil).new

    Mantle::LogContext.with_sequence_id("parent-seq") do
      seq = Mantle::LogContext.sequence_id
      spawn do
        Mantle::LogContext.with_sequence_id(seq.not_nil!) do
          client.execute(messages)
          channel.send(nil)
        end
      end
    end

    channel.receive

    lines = File.read_lines(log_file)
    json = JSON.parse(lines.first)
    json["sequence_id"].as_s.should eq("parent-seq")
  end
end
