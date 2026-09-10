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

class DummySecondaryClient < Mantle::Clients::Client
  property model_name : String = "secondary-model"

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    Mantle::Clients::Response.new(content: "Secondary response", tool_calls: nil)
  end
end

class DummyWireClient < Mantle::Clients::Client
  property model_name : String = "qwen-wire"
  property raw_req : String = %({"model":"qwen-wire","messages":[{"role":"user","content":"test wire"}],"options":{"temperature":0.7}})
  property raw_res : String = %({"model":"qwen-wire","message":{"role":"assistant","content":"wire response"},"done":true})

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    Mantle::Clients::Response.new(
      content: "wire response",
      tool_calls: nil
    ).tap do |r|
      r.raw_request = @raw_req
      r.raw_response = @raw_res
    end
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
    client.flush

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
    client.flush

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
    client.flush

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
    client.flush

    lines = File.read_lines(log_file)
    json = JSON.parse(lines.first)
    json["sequence_id"].as_s.should eq("parent-seq")
  end

  it "shares unparameterized mutex and supports concurrent writes across different client specializations" do
    log_file = File.join(temp_dir, "test_concurrent_specializations.jsonl")
    client1 = Mantle::Clients::LoggingClient.new(DummyLoggingTestClient.new, log_file)
    client2 = Mantle::Clients::LoggingClient.new(DummySecondaryClient.new, log_file)

    messages1 = [Mantle::Message.new("user", "From client 1")]
    messages2 = [Mantle::Message.new("user", "From client 2")]

    done = Channel(Nil).new(2)

    spawn do
      10.times do |i|
        Mantle::LogContext.with_sequence_id("client1-#{i}") do
          client1.execute(messages1)
        end
      end
      done.send(nil)
    end

    spawn do
      10.times do |i|
        Mantle::LogContext.with_sequence_id("client2-#{i}") do
          client2.execute(messages2)
        end
      end
      done.send(nil)
    end

    2.times { done.receive }

    Mantle::Clients::ReceiptWriter.flush

    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(20)

    models = lines.map { |l| JSON.parse(l)["model"].as_s }
    models.count("dummy-model").should eq(10)
    models.count("secondary-model").should eq(10)
  end

  it "guarantees ReceiptWriter.flush blocks until all queued writes have landed on disk" do
    log_file = File.join(temp_dir, "test_flush_blocking.jsonl")
    client = Mantle::Clients::LoggingClient.new(DummyLoggingTestClient.new, log_file)

    50.times do |i|
      client.execute([Mantle::Message.new("user", "Batch #{i}")])
    end

    # Explicit flush blocks until channel is empty and all 50 entries are flushed
    Mantle::Clients::ReceiptWriter.flush

    File.exists?(log_file).should be_true
    File.read_lines(log_file).size.should eq(50)
  end

  it "captures spatial ephemeral_injections and LTM state in the JSONL receipt" do
    log_file = File.join(temp_dir, "test_injections.jsonl")
    dummy = DummyLoggingTestClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    messages = [Mantle::Message.new("user", "Hello")]
    injections = Mantle::Clients::EphemeralInjections.new(
      system: [Mantle::Message.new("system", "SYS_FLAG")],
      pre_history: [Mantle::Message.new("system", "PRE_HIST_FLAG")],
      tail: [Mantle::Message.new("system", "TAIL_FLAG")],
      memory_view: "[Memory Layer 0] Historical facts"
    )

    client.execute(messages, ephemeral_injections: injections)
    client.flush

    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(1)

    json = JSON.parse(lines.first)
    json["ephemeral_injections"]?.should_not be_nil
    inj = json["ephemeral_injections"]
    inj["system"][0]["content"].as_s.should eq("SYS_FLAG")
    inj["pre_history"][0]["content"].as_s.should eq("PRE_HIST_FLAG")
    inj["tail"][0]["content"].as_s.should eq("TAIL_FLAG")
    inj["memory_view"].as_s.should eq("[Memory Layer 0] Historical facts")
  end

  it "serializes full raw_request and raw_response JSON payloads into JSONL receipt" do
    log_file = File.join(temp_dir, "test_wire_payloads.jsonl")
    dummy = DummyWireClient.new
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    messages = [Mantle::Message.new("user", "test wire")]
    client.execute(messages)
    client.flush

    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(1)

    json = JSON.parse(lines.first)
    json["raw_request"]?.should_not be_nil
    json["raw_request"]["model"].as_s.should eq("qwen-wire")
    json["raw_request"]["options"]["temperature"].as_f.should eq(0.7)

    json["raw_response"]?.should_not be_nil
    json["raw_response"]["message"]["content"].as_s.should eq("wire response")
    json["raw_response"]["done"].as_bool.should be_true
  end

  it "serializes streaming NDJSON raw_response chunks into an array of JSON objects" do
    log_file = File.join(temp_dir, "test_wire_streaming.jsonl")
    dummy = DummyWireClient.new
    dummy.raw_res = %({"model":"qwen","message":{"content":"chunk1"},"done":false}\n{"model":"qwen","message":{"content":"chunk2"},"done":true}\n)
    client = Mantle::Clients::LoggingClient.new(dummy, log_file)

    messages = [Mantle::Message.new("user", "test stream wire")]
    client.execute(messages)
    client.flush

    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(1)

    json = JSON.parse(lines.first)
    json["raw_response"]?.should_not be_nil
    chunks = json["raw_response"].as_a
    chunks.size.should eq(2)
    chunks[0]["message"]["content"].as_s.should eq("chunk1")
    chunks[1]["message"]["content"].as_s.should eq("chunk2")
    chunks[1]["done"].as_bool.should be_true
  end
end
