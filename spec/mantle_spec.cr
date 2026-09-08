# spec/mantle_spec.cr
require "./spec_helper"

describe Mantle::Step do
  it "executes inference and returns a StepResult with the model response" do
    client = DummyClient.new
    step = Mantle::Step.new(client)

    messages = [
      Mantle::Message.new("system", "Sys Prompt"),
      Mantle::Message.new("user", "Hello"),
    ]

    result = step.run(messages)

    result.ok?.should be_true
    result.err?.should be_false
    result.value.should eq("Simulated response")
    result.unwrap.should eq("Simulated response")
    result.iterations.should eq(1)
  end

  it "streams chunks to block during execution" do
    client = DummyClient.new
    step = Mantle::Step.new(client)

    messages = [Mantle::Message.new("user", "What is 2+2?")]
    chunks = [] of String
    result = step.run(messages) do |chunk|
      chunks << chunk
    end

    result.ok?.should be_true
    chunks.should eq(["Simulated response"])
  end

  it "integrates with ContextManager for conversational turns" do
    store = DummyContextStore.new("Sys Prompt")
    context_manager = DummyContextManager.new(store)
    client = DummyClient.new
    step = Mantle::Step.new(client)

    # Turn 1
    context_manager.add_user_message("Turn 1")
    res1 = step.run(context_manager.project_view)
    res1.ok?.should be_true
    context_manager.add_assistant_message(res1.unwrap)

    # Turn 2
    context_manager.add_user_message("Turn 2")
    res2 = step.run(context_manager.project_view)
    res2.ok?.should be_true
    context_manager.add_assistant_message(res2.unwrap)

    view = store.current_view
    messages_content = view.map { |m| m.content }

    messages_content.should contain("Turn 1")
    messages_content.should contain("Turn 2")
    turn1_index = view.index { |m| m.content == "Turn 1" }
    turn2_index = view.index { |m| m.content == "Turn 2" }
    turn1_index.should_not be_nil
    turn2_index.should_not be_nil
    turn1_index.not_nil!.should be < turn2_index.not_nil!
  end
end
