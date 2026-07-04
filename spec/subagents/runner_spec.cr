require "../spec_helper"
require "../../src/mantle/subagents/runner"

class DelayedMockClient < Mantle::Clients::Client
  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    sleep 0.1
    Mantle::Clients::Response.new(content: "Delayed response", tool_calls: nil)
  end
end

describe Mantle::Subagents::Runner do
  it "spawns an interactive subagent without blocking the main fiber" do
    profile = Mantle::Subagents::Profile.new(
      id: "tester",
      name: "Tester",
      description: "A test profile",
      system_prompt: "You are a test subagent.",
      max_tokens: 100,
      temperature: 0.1
    )
    runner = Mantle::Subagents::Runner.new(
      profiles: {"tester" => profile},
      client: DelayedMockClient.new
    )

    concurrent_flag = false
    channel = Channel(Nil).new

    # Spawn subagent interactively
    runner.spawn_interactive("tester", "Hello", "Context", 1) do |content|
      # Do nothing
    end

    # Meanwhile, on the main fiber
    spawn do
      concurrent_flag = true
      channel.send(nil)
    end

    channel.receive
    concurrent_flag.should be_true
  end

  it "enforces depth limit at the boundary" do
    profile = Mantle::Subagents::Profile.new(
      id: "tester",
      name: "Tester",
      description: "A test profile",
      system_prompt: "You are a test subagent.",
      max_tokens: 100,
      temperature: 0.1
    )
    # Default max_depth is 1
    runner = Mantle::Subagents::Runner.new(
      profiles: {"tester" => profile},
      client: DelayedMockClient.new
    )

    # Should succeed at depth 1
    result = runner.spawn("tester", "Hello", "Context", 1)
    result.should contain("[Subagent: Tester]")

    # Should raise at depth 2
    expect_raises(Exception, "Subagent depth limit exceeded: 2 > 1") do
      runner.spawn("tester", "Hello", "Context", 2)
    end
  end
end
