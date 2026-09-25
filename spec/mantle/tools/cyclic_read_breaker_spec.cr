require "../../spec_helper"
require "../../../src/mantle/tools/middleware"

describe Mantle::Tools::Middleware::CyclicReadBreaker do
  it "passes through diverse inspection calls without tripping" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 3)
    handler = ->(args : Hash(String, JSON::Any)) { "content of #{args["path"]}" }

    res1 = breaker.call("read_file", {"path" => JSON::Any.new("a.cr")}, handler)
    res2 = breaker.call("read_file", {"path" => JSON::Any.new("b.cr")}, handler)
    res3 = breaker.call("read_file", {"path" => JSON::Any.new("c.cr")}, handler)

    res1.should eq("content of a.cr")
    res2.should eq("content of b.cr")
    res3.should eq("content of c.cr")
    breaker.tripped?.should be_false
  end

  it "trips soft refusal when identical inspection call reaches threshold" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 3)
    handler = ->(args : Hash(String, JSON::Any)) { "file content" }

    breaker.call("read_file", {"path" => JSON::Any.new("same.cr")}, handler).should eq("file content")
    breaker.call("read_file", {"path" => JSON::Any.new("same.cr")}, handler).should eq("file content")

    # 3rd identical call trips
    tripped_res = breaker.call("read_file", {"path" => JSON::Any.new("same.cr")}, handler)
    breaker.tripped?.should be_true
    tripped_res.should contain("ERR_CYCLIC_READ")
    tripped_res.should contain(%("refused":true))

    parsed = JSON.parse(tripped_res)
    parsed["refused"].as_bool.should be_true
  end

  it "raises TerminalToolError when raise_on_trip is true" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 2, raise_on_trip: true)
    handler = ->(args : Hash(String, JSON::Any)) { "ok" }

    breaker.call("read_file", {"path" => JSON::Any.new("file.cr")}, handler)

    expect_raises(Mantle::Tools::TerminalToolError, /ERR_CYCLIC_READ/) do
      breaker.call("read_file", {"path" => JSON::Any.new("file.cr")}, handler)
    end
  end

  it "resets inspection count when a mutation tool succeeds" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 3)
    read_handler = ->(args : Hash(String, JSON::Any)) { "content" }
    write_handler = ->(args : Hash(String, JSON::Any)) { %({"success":true}) }

    breaker.call("read_file", {"path" => JSON::Any.new("target.cr")}, read_handler)
    breaker.call("read_file", {"path" => JSON::Any.new("target.cr")}, read_handler)
    breaker.inspection_history[{"read_file", %({"path":"target.cr"})}]?.should eq(2)

    # Workspace mutation occurs
    breaker.call("write_file", {"path" => JSON::Any.new("target.cr"), "content" => JSON::Any.new("new")}, write_handler)

    # Counters should be cleared
    breaker.inspection_history.should be_empty

    # Next read should not trip
    breaker.call("read_file", {"path" => JSON::Any.new("target.cr")}, read_handler).should eq("content")
    breaker.tripped?.should be_false
  end

  it "resets inspection counts when record_mutation is invoked manually" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 2)
    handler = ->(args : Hash(String, JSON::Any)) { "content" }

    breaker.call("read_file", {"path" => JSON::Any.new("file.cr")}, handler)
    breaker.inspection_history.size.should eq(1)

    breaker.record_mutation
    breaker.inspection_history.should be_empty
  end

  it "does not track or constrain non-inspection tools" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 2)
    handler = ->(args : Hash(String, JSON::Any)) { "command output" }

    # Run non-inspection tool (like a build command) 5 times
    5.times do
      res = breaker.call("run_shell", {"command" => JSON::Any.new("shards build")}, handler)
      res.should eq("command output")
    end

    breaker.tripped?.should be_false
    breaker.inspection_history.should be_empty
  end

  it "evicts older inspection calls when window_size is configured" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 2, window_size: 2)
    handler = ->(args : Hash(String, JSON::Any)) { "content" }

    # Call A
    breaker.call("read_file", {"path" => JSON::Any.new("a.cr")}, handler)
    breaker.inspection_history[{"read_file", %({"path":"a.cr"})}]?.should eq(1)

    # Call B, C (pushing A out of window)
    breaker.call("read_file", {"path" => JSON::Any.new("b.cr")}, handler)
    breaker.call("read_file", {"path" => JSON::Any.new("c.cr")}, handler)

    # A should be evicted
    breaker.inspection_history.has_key?({"read_file", %({"path":"a.cr"})}).should be_false

    # Re-reading A now should be count 1, not 2, so it shouldn't trip
    breaker.call("read_file", {"path" => JSON::Any.new("a.cr")}, handler)
    breaker.tripped?.should be_false
  end

  it "wraps tools seamlessly via ToolMiddleware.wrap" do
    breaker = Mantle::Tools::Middleware::CyclicReadBreaker.new(threshold: 2)
    func = Mantle::Tools::FunctionDefinition.new(
      name: "read_file",
      description: "Read file",
      parameters: Mantle::Tools::ParametersSchema.new({} of String => Mantle::Tools::PropertyDefinition)
    )
    raw_tool = Mantle::Tools::Tool.new(func) do |args|
      "raw content #{args["p"]}"
    end

    wrapped_tool = Mantle::Tools::Middleware.wrap(raw_tool, [breaker])

    wrapped_tool.execute({"p" => JSON::Any.new("x")}).should eq("raw content x")
    tripped = wrapped_tool.execute({"p" => JSON::Any.new("x")})
    tripped.should contain("ERR_CYCLIC_READ")
  end
end
