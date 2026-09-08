require "../spec_helper"
require "file_utils"
require "json"

# Mock Step client to test session pipeline
class SessionMockClient < Mantle::Clients::Client
  property responses : Array(Mantle::Clients::Response)
  property call_count : Int32 = 0
  property should_raise : Exception? = nil

  def initialize(@responses : Array(Mantle::Clients::Response) = [] of Mantle::Clients::Response)
  end

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    if ex = @should_raise
      raise ex
    end

    resp = if @call_count < @responses.size
             @responses[@call_count]
           else
             @responses.last? || Mantle::Clients::Response.new(content: "Default response", tool_calls: nil)
           end
    @call_count += 1
    if c = resp.content
      on_chunk.call(c)
    end
    resp
  end
end

describe Mantle::Session do
  temp_dir = File.join(Dir.tempdir, "session_spec_#{Random.rand(100000)}")

  before_each do
    Dir.mkdir_p(temp_dir)
  end

  after_each do
    FileUtils.rm_rf(temp_dir) if Dir.exists?(temp_dir)
  end

  it "orchestrates full turn lifecycle: commit trigger, project injections, execute step, commit assistant, emit receipt" do
    log_file = File.join(temp_dir, "session_receipts.jsonl")

    client = SessionMockClient.new([
      Mantle::Clients::Response.new(content: "I am ready to assist.", tool_calls: nil),
    ])
    step = Mantle::Step.new(client)

    context_store = DummyContextStore.new("Base Persona")
    context_manager = Mantle::Storage::ContextManager.new(
      context_store: context_store,
      memory_store: DummyMemoryStore.new,
      user_name: "Cam",
      bot_name: "Adjutant"
    )

    session = Mantle::Session.new(
      context_manager: context_manager,
      step: step,
      log_file: log_file,
      model_name: "test-model"
    )

    chunks = [] of String
    result = session.run_turn(
      trigger: "Hello Adjutant",
      system_injections: ["Role: Senior Architect"],
      pre_history_injections: ["Topic: Infrastructure"],
      tail_injections: ["Answer concisely"]
    ) do |chunk|
      chunks << chunk
    end

    result.ok?.should be_true
    result.value.should eq("I am ready to assist.")
    chunks.should eq(["I am ready to assist."])

    # Verify context store has user and assistant messages committed
    messages = context_store.messages
    messages.size.should eq(2)
    messages[0].role.should eq("user")
    messages[0].content.should eq("Hello Adjutant")
    messages[1].role.should eq("assistant")
    messages[1].content.should eq("I am ready to assist.")

    # Flush receipts and verify audit file
    Mantle::Clients::ReceiptWriter.flush
    File.exists?(log_file).should be_true
    lines = File.read_lines(log_file)
    lines.size.should eq(1)

    receipt = JSON.parse(lines.first)
    receipt["status"].as_s.should eq("success")
    receipt["model"].as_s.should eq("test-model")
    receipt["raw_output"]["content"].as_s.should eq("I am ready to assist.")

    injections = receipt["ephemeral_injections"]
    injections["system"][0]["content"].as_s.should eq("Role: Senior Architect")
    injections["pre_history"][0]["content"].as_s.should eq("Topic: Infrastructure")
    injections["tail"][0]["content"].as_s.should eq("Answer concisely")
  end

  it "enforces idempotency contract: retrying a failed turn does not duplicate the trigger message in context" do
    client = SessionMockClient.new
    client.should_raise = IO::Error.new("Connection timed out")

    step = Mantle::Step.new(client)
    context_store = DummyContextStore.new("Base Persona")
    context_manager = Mantle::Storage::ContextManager.new(
      context_store: context_store,
      memory_store: DummyMemoryStore.new,
      user_name: "Cam",
      bot_name: "Adjutant"
    )

    session = Mantle::Session.new(context_manager, step)

    # First attempt: fails with ClientFailure (retryable)
    result1 = session.run_turn("Process batch #1")
    result1.err?.should be_true
    result1.error.should eq(Mantle::StepError::ClientFailure)
    result1.error.not_nil!.retryable?.should be_true

    # The trigger message should be committed once
    context_store.messages.size.should eq(1)
    context_store.messages[0].content.should eq("Process batch #1")

    # Second attempt: network recovered
    client.should_raise = nil
    client.responses = [Mantle::Clients::Response.new(content: "Batch #1 completed", tool_calls: nil)]

    # Retry the turn with is_retry: true
    result2 = session.run_turn("Process batch #1", is_retry: true)
    result2.ok?.should be_true
    result2.value.should eq("Batch #1 completed")

    # Idempotency check: context store must have only ONE user message, not two!
    messages = context_store.messages
    messages.size.should eq(2) # 1 user, 1 assistant
    messages[0].role.should eq("user")
    messages[0].content.should eq("Process batch #1")
    messages[1].role.should eq("assistant")
    messages[1].content.should eq("Batch #1 completed")
  end

  it "does not corrupt the context graph on unrecoverable failure" do
    client = SessionMockClient.new
    client.should_raise = Exception.new("Malformed response")

    step = Mantle::Step.new(client)
    context_store = DummyContextStore.new("Base")
    context_manager = Mantle::Storage::ContextManager.new(context_store, DummyMemoryStore.new, "User", "Bot")
    session = Mantle::Session.new(context_manager, step)

    result = session.run_turn("Bad turn")
    result.err?.should be_true

    # Only the user trigger was recorded; no partial assistant turn or corruption
    context_store.messages.size.should eq(1)
    context_store.messages[0].role.should eq("user")
  end

  it "routes messages in consume_queue with backoff retries and dead-lettering" do
    inbox = Channel(Mantle::Session::QueueItem).new(5)
    outbox = Channel(Mantle::StepResult(String, Mantle::StepError)).new(5)
    dead_letter = Channel(Tuple(Mantle::Session::QueueItem, Mantle::StepError)).new(5)

    client = SessionMockClient.new
    client.should_raise = IO::Error.new("Simulated 502 Bad Gateway") # Retryable error

    step = Mantle::Step.new(client)
    context_store = DummyContextStore.new("Base")
    context_manager = Mantle::Storage::ContextManager.new(context_store, DummyMemoryStore.new, "User", "Bot")
    session = Mantle::Session.new(context_manager, step)

    # Queue item with max_retries: 1
    item = Mantle::Session::QueueItem.new(
      trigger: "Queue trigger",
      max_retries: 1
    )
    inbox.send(item)

    # Run queue consumer in fiber
    spawn do
      session.consume_queue(inbox: inbox, outbox: outbox, dead_letter: dead_letter, backoff_ms: 10)
    end

    # Should land on dead-letter after exhausting 1 retry
    failed_item, err = dead_letter.receive
    failed_item.trigger.should eq("Queue trigger")
    err.should eq(Mantle::StepError::ClientFailure)

    # Outbox receives the terminal failure result
    res = outbox.receive
    res.err?.should be_true
  end
end
