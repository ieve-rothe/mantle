require "../spec_helper"

class DummyStatusClient < Mantle::Clients::Client
  property next_response : Mantle::Clients::Response = Mantle::Clients::Response.new(content: "OK", tool_calls: nil)

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil) : Mantle::Clients::Response
    @next_response
  end

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    on_chunk.call(@next_response.content || "")
    @next_response
  end
end

describe "Mantle Instance-Level Status Callbacks" do
  describe "ContextManager#on_status" do
    it "triggers on_status when consolidation occurs" do
      context_store = Mantle::Storage::EphemeralSlidingContextStore.new("System prompt", 10)
      memory_file = File.tempname("memory", ".json")
      begin
        squishifier = ->(msgs : Array(String)) { "summary" }
        memory_store = Mantle::Storage::JSONLayeredMemoryStore.new(memory_file, 100, 50, squishifier)
        events = [] of Symbol

        cm = Mantle::Storage::ContextManager.new(
          context_store,
          memory_store,
          "User",
          "Bot",
          on_status: ->(flag : Symbol) { events << flag }
        )

        cm.consolidate_memory
        events.should eq([:memory_consolidation])
      ensure
        File.delete(memory_file) if File.exists?(memory_file)
      end
    end
  end

  describe "Step#on_status" do
    it "triggers Step#on_status during execution" do
      client = DummyStatusClient.new
      events = [] of Symbol
      step = Mantle::Step.new(client, on_status: ->(flag : Symbol) { events << flag })

      client.next_response = Mantle::Clients::Response.new(content: "Hello response", tool_calls: nil)
      messages = [Mantle::Message.new("user", "Hello")]
      res = step.run(messages)
      res.ok?.should be_true
      events.should eq([:awaiting_inference, :idle])
    end
  end
end
