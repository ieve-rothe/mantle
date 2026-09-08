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

  describe "Flow#on_status" do
    it "triggers ChatFlow#on_status on run completion" do
      context_store = Mantle::Storage::EphemeralSlidingContextStore.new("System prompt", 10)
      memory_file = File.tempname("memory", ".json")
      begin
        squishifier = ->(msgs : Array(String)) { "summary" }
        memory_store = Mantle::Storage::JSONLayeredMemoryStore.new(memory_file, 100, 50, squishifier)
        cm = Mantle::Storage::ContextManager.new(context_store, memory_store, "User", "Bot")
        client = DummyStatusClient.new

        events = [] of Symbol
        flow = Mantle::Flows::ChatFlow.new(cm, client, on_status: ->(flag : Symbol) { events << flag })

        client.next_response = Mantle::Clients::Response.new(content: "Hello response", tool_calls: nil)
        flow.run("Hello", ->(resp : Mantle::Clients::Response) { })

        events.should eq([:idle])
      ensure
        File.delete(memory_file) if File.exists?(memory_file)
      end
    end

    it "triggers ToolEnabledChatFlow#on_status during tool execution and completion" do
      context_store = Mantle::Storage::EphemeralSlidingContextStore.new("System prompt", 10)
      memory_file = File.tempname("memory", ".json")
      begin
        squishifier = ->(msgs : Array(String)) { "summary" }
        memory_store = Mantle::Storage::JSONLayeredMemoryStore.new(memory_file, 100, 50, squishifier)
        cm = Mantle::Storage::ContextManager.new(context_store, memory_store, "User", "Bot")
        client = DummyStatusClient.new

        events = [] of Symbol
        flow = Mantle::Flows::ToolEnabledChatFlow.new(cm, client, on_status: ->(flag : Symbol) { events << flag })

        client.next_response = Mantle::Clients::Response.new(content: "Done!", tool_calls: nil)
        flow.run("Run flow", on_response: ->(resp : Mantle::Clients::Response) { })

        events.should eq([:idle])
      ensure
        File.delete(memory_file) if File.exists?(memory_file)
      end
    end
  end
end
