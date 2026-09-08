require "../../spec_helper"

class CustomLtmMemoryStore < DummyMemoryStore
  def current_view
    "LTM: Consolidated memory facts"
  end
end

describe "Mantle::Storage::ContextManager Projection & Injections" do
  it "places system_injections, LTM view, pre_history_injections, and tail_injections in exact spatial order" do
    context_store = DummyContextStore.new("Base System Instructions")
    memory_store = CustomLtmMemoryStore.new

    manager = Mantle::Storage::ContextManager.new(
      context_store: context_store,
      memory_store: memory_store,
      user_name: "User",
      bot_name: "Assistant"
    )

    # Commit canonical conversation messages
    manager << "Hello from User"
    manager.add_assistant_message("Hello back")

    # Call project_view with spatial injections
    system_inj = [Mantle::Message.new("system", "SYS_INJECTION_1")]
    pre_hist_inj = [Mantle::Message.new("system", "PRE_HIST_INJECTION_1")]
    tail_inj = [Mantle::Message.new("system", "TAIL_INJECTION_1")]

    view = manager.project_view(
      system_injections: system_inj,
      pre_history_injections: pre_hist_inj,
      tail_injections: tail_inj
    )

    # Expected order:
    # 0: Base System Prompt
    # 1: System Injections
    # 2: LTM view
    # 3: Pre-History Injections
    # 4: Canonical user message
    # 5: Canonical assistant message
    # 6: Tail Injections
    view.size.should eq(7)
    view[0].content.should eq("Base System Instructions")
    view[1].content.should eq("SYS_INJECTION_1")
    view[2].content.should eq("LTM: Consolidated memory facts")
    view[3].content.should eq("PRE_HIST_INJECTION_1")
    view[4].content.should eq("Hello from User")
    view[5].content.should eq("Hello back")
    view[6].content.should eq("TAIL_INJECTION_1")
  end

  it "does not mutate the canonical graph during view projection" do
    context_store = DummyContextStore.new("Base System")
    manager = Mantle::Storage::ContextManager.new(
      context_store: context_store,
      memory_store: DummyMemoryStore.new,
      user_name: "User",
      bot_name: "Assistant"
    )

    manager << "Turn 1"
    initial_graph_size = context_store.current_num_messages

    # Project view with injections multiple times
    3.times do
      manager.project_view(
        system_injections: [Mantle::Message.new("system", "Transient SYS")],
        tail_injections: [Mantle::Message.new("system", "Transient TAIL")]
      )
    end

    # Graph size must be completely unchanged
    context_store.current_num_messages.should eq(initial_graph_size)
  end

  it "does not retain ephemeral injections across subsequent calls to project_view" do
    context_store = DummyContextStore.new("Base System")
    manager = Mantle::Storage::ContextManager.new(
      context_store: context_store,
      memory_store: DummyMemoryStore.new,
      user_name: "User",
      bot_name: "Assistant"
    )

    manager << "User message"

    view_with_inj = manager.project_view(
      system_injections: ["Temp rule"],
      tail_injections: ["Temp nudge"]
    )
    view_with_inj.any? { |m| m.content == "Temp rule" }.should be_true
    view_with_inj.any? { |m| m.content == "Temp nudge" }.should be_true

    view_without_inj = manager.project_view
    view_without_inj.any? { |m| m.content == "Temp rule" }.should be_false
    view_without_inj.any? { |m| m.content == "Temp nudge" }.should be_false
  end

  it "supports << operator for Strings and typed Messages with method chaining" do
    context_store = DummyContextStore.new("System")
    manager = Mantle::Storage::ContextManager.new(
      context_store: context_store,
      memory_store: DummyMemoryStore.new,
      user_name: "User",
      bot_name: "Assistant"
    )

    # Chain string (defaults to user) and typed system message
    manager << "User line 1" << Mantle::Message.new(role: "system", content: "DAEMON_INTERRUPT") << "User line 2"

    messages = context_store.messages
    messages.size.should eq(3)
    messages[0].role.should eq("user")
    messages[0].content.should eq("User line 1")
    messages[1].role.should eq("system")
    messages[1].content.should eq("DAEMON_INTERRUPT")
    messages[2].role.should eq("user")
    messages[2].content.should eq("User line 2")
  end
end
