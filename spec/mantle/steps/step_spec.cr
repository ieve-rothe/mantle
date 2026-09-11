require "../../spec_helper"

# Mock client that simulates sequential scripted responses
class StepMockClient < Mantle::Clients::Client
  property responses : Array(Mantle::Clients::Response)
  property call_count : Int32 = 0
  property recorded_messages : Array(Array(Mantle::Message)) = [] of Array(Mantle::Message)
  property should_raise : Exception? = nil

  def initialize(@responses : Array(Mantle::Clients::Response))
  end

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    @recorded_messages << messages.dup
    if ex = @should_raise
      raise ex
    end

    if @call_count < @responses.size
      response = @responses[@call_count]
    else
      response = @responses.last
    end
    @call_count += 1

    if content = response.content
      on_chunk.call(content) unless content.empty?
    end

    response
  end
end

describe Mantle::Step do
  describe "standard text response generation" do
    it "executes inference and returns a StepResult with text" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(content: "Hello from LLM", tool_calls: nil),
      ])
      step = Mantle::Step.new(client)

      messages = [Mantle::Message.new("user", "Hello")]
      result = step.run(messages)

      result.ok?.should be_true
      result.err?.should be_false
      result.value.should eq("Hello from LLM")
      result.unwrap.should eq("Hello from LLM")
      result.iterations.should eq(1)
      client.call_count.should eq(1)
    end
  end

  describe "token streaming via &block" do
    it "yields streamed chunks to caller block" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(content: "TokenStream", tool_calls: nil),
      ])
      step = Mantle::Step.new(client)

      received_chunks = [] of String
      messages = [Mantle::Message.new("user", "Stream tokens")]
      result = step.run(messages) do |chunk|
        received_chunks << chunk
      end

      result.ok?.should be_true
      received_chunks.should eq(["TokenStream"])
    end
  end

  describe "multi-step tool calling loop up to resolution" do
    it "executes tools and continues loop until final text response" do
      client = StepMockClient.new([
        # Turn 1: Model requests tool_1
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_1",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(
                name: "lookup_user",
                arguments: %({"username":"cam"})
              )
            ),
          ]
        ),
        # Turn 2: Model requests tool_2
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_2",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(
                name: "lookup_role",
                arguments: %({"user_id":"123"})
              )
            ),
          ]
        ),
        # Turn 3: Final text answer
        Mantle::Clients::Response.new(
          content: "Cam is an administrator.",
          tool_calls: nil
        ),
      ])

      tools = [
        Mantle::Tools::Tool.new(
          function: Mantle::Tools::FunctionDefinition.new(
            name: "lookup_user",
            description: "Find user by username",
            parameters: Mantle::Tools::ParametersSchema.new(
              properties: {"username" => Mantle::Tools::PropertyDefinition.new("string", "Username")}
            )
          )
        ) do |args|
          %({"user_id":"123","status":"active"})
        end,
        Mantle::Tools::Tool.new(
          function: Mantle::Tools::FunctionDefinition.new(
            name: "lookup_role",
            description: "Find role by user_id",
            parameters: Mantle::Tools::ParametersSchema.new(
              properties: {"user_id" => Mantle::Tools::PropertyDefinition.new("string", "User ID")}
            )
          )
        ) do |args|
          %({"role":"administrator"})
        end,
      ]

      step = Mantle::Step.new(client, tools)
      messages = [Mantle::Message.new("user", "What is Cam's role?")]

      result = step.run(messages)

      result.ok?.should be_true
      result.unwrap.should eq("Cam is an administrator.")
      result.iterations.should eq(3)
      client.call_count.should eq(3)

      # Verify tool messages were preserved in intermediate context
      last_recorded_messages = client.recorded_messages.last
      last_recorded_messages.size.should eq(5) # user, assistant(call_1), tool(res_1), assistant(call_2), tool(res_2)
      last_recorded_messages[1].role.should eq("assistant")
      last_recorded_messages[2].role.should eq("tool")
      last_recorded_messages[2].tool_call_id.should eq("call_1")
      last_recorded_messages[3].role.should eq("assistant")
      last_recorded_messages[4].role.should eq("tool")
      last_recorded_messages[4].tool_call_id.should eq("call_2")
    end
  end

  describe "graceful termination when reaching max_iterations" do
    it "aborts and returns StepResult.error(MaxIterationsReached) without raising" do
      # Client always emits a tool call
      infinite_tool_response = Mantle::Clients::Response.new(
        content: nil,
        tool_calls: [
          Mantle::Clients::ToolCall.new(
            id: "loop_call",
            type: "function",
            function: Mantle::Clients::ToolCallFunction.new(
              name: "ping",
              arguments: %({})
            )
          ),
        ]
      )
      client = StepMockClient.new([infinite_tool_response])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "ping",
          description: "Ping",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) do |_|
        %({"pong":true})
      end

      step = Mantle::Step.new(client, [tool], max_iterations: 3)
      messages = [Mantle::Message.new("user", "Start loop")]

      result = step.run(messages)

      result.err?.should be_true
      result.ok?.should be_false
      result.error.should eq(Mantle::StepError::MaxIterationsReached)
      result.iterations.should eq(3)
      client.call_count.should eq(3)
    end
  end

  describe "instance @on_status hook invocation" do
    it "emits lifecycle flags during tool and inference phases" do
      client = StepMockClient.new([
        # Iteration 1: calls tool
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_a",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "test_tool", arguments: %({}))
            ),
          ]
        ),
        # Iteration 2: returns final response
        Mantle::Clients::Response.new(
          content: "All done",
          tool_calls: nil
        ),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "test_tool",
          description: "Test tool",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) do |_|
        %({"result":"ok"})
      end

      status_events = [] of Symbol
      step = Mantle::Step.new(
        client,
        [tool],
        on_status: ->(flag : Symbol) { status_events << flag }
      )

      messages = [Mantle::Message.new("user", "Execute")]
      result = step.run(messages)

      result.ok?.should be_true
      status_events.should eq([
        :thinking,
        :tool_loop,
        :thinking,
        :idle,
      ])
    end
  end

  describe "failure modes and resilience" do
    it "returns ClientFailure when client raises an exception" do
      client = StepMockClient.new([] of Mantle::Clients::Response)
      client.should_raise = IO::Error.new("Connection refused")

      step = Mantle::Step.new(client)
      messages = [Mantle::Message.new("user", "Hello")]
      result = step.run(messages)

      result.err?.should be_true
      result.error.should eq(Mantle::StepError::ClientFailure)
    end

    it "returns ToolExecutionFailure when tool execution raises an unhandled error" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_err",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "failing_tool", arguments: %({}))
            ),
          ]
        ),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "failing_tool",
          description: "Fails",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) do |_|
        raise "Unexpected tool crash"
      end

      step = Mantle::Step.new(client, [tool])
      messages = [Mantle::Message.new("user", "Run failing tool")]
      result = step.run(messages)

      result.err?.should be_true
      result.error.should eq(Mantle::StepError::ToolExecutionFailure)
    end

    it "returns MalformedOutput when LLM outputs invalid JSON for tool arguments" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "bad_json_call",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "any_tool", arguments: "not valid json {")
            ),
          ]
        ),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "any_tool",
          description: "Any",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) do |_|
        "ok"
      end

      step = Mantle::Step.new(client, [tool])
      messages = [Mantle::Message.new("user", "Trigger bad JSON")]
      result = step.run(messages)

      result.err?.should be_true
      result.error.should eq(Mantle::StepError::MalformedOutput)
    end

    it "returns MalformedOutput when LLM returns neither content nor tool calls" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: nil
        ),
      ])

      step = Mantle::Step.new(client)
      messages = [Mantle::Message.new("user", "Hello")]
      result = step.run(messages)

      result.err?.should be_true
      result.error.should eq(Mantle::StepError::MalformedOutput)
    end

    it "treats caller message array as immutable and does not mutate it during tool loops" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_a",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "dummy_tool", arguments: %({}))
            ),
          ]
        ),
        Mantle::Clients::Response.new(content: "Done", tool_calls: nil),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "dummy_tool",
          description: "desc",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) { |_| "ok" }

      step = Mantle::Step.new(client, [tool])
      caller_messages = [Mantle::Message.new("user", "Run tool")]
      result = step.run(caller_messages)

      result.ok?.should be_true
      # Caller's input array must remain completely untouched!
      caller_messages.size.should eq(1)
      caller_messages.first.content.should eq("Run tool")
    end

    it "correctly classifies StepError into retryable? and terminal?" do
      Mantle::StepError::ClientFailure.retryable?.should be_true
      Mantle::StepError::ClientFailure.terminal?.should be_false

      Mantle::StepError::RateLimited.retryable?.should be_true
      Mantle::StepError::RateLimited.terminal?.should be_false

      Mantle::StepError::MalformedOutput.retryable?.should be_false
      Mantle::StepError::MalformedOutput.terminal?.should be_true

      Mantle::StepError::MaxIterationsReached.retryable?.should be_false
      Mantle::StepError::MaxIterationsReached.terminal?.should be_true

      Mantle::StepError::ToolExecutionFailure.retryable?.should be_false
      Mantle::StepError::ToolExecutionFailure.terminal?.should be_true
    end

    it "identifies RateLimited errors when client raises 429 or rate limit message" do
      client = StepMockClient.new([] of Mantle::Clients::Response)
      client.should_raise = Exception.new("429 Too Many Requests: rate limit exceeded")

      step = Mantle::Step.new(client)
      result = step.run([Mantle::Message.new("user", "Hello")])

      result.err?.should be_true
      result.error.should eq(Mantle::StepError::RateLimited)
      result.error.not_nil!.retryable?.should be_true
    end
  end

  describe "on_iteration hook (TKT-008)" do
    it "is inert when nil (default)" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(content: "Done", tool_calls: nil),
      ])
      step = Mantle::Step.new(client)
      step.on_iteration.should be_nil

      result = step.run([Mantle::Message.new("user", "Hello")])
      result.ok?.should be_true
      client.call_count.should eq(1)
      client.recorded_messages.size.should eq(1)
      client.recorded_messages.first.first.content.should eq("Hello")
    end

    it "invokes the hook before each inference call with working buffer and last_response" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_1",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "tool_a", arguments: %({}))
            ),
          ],
          prompt_eval_count: 42
        ),
        Mantle::Clients::Response.new(content: "Final answer", tool_calls: nil, prompt_eval_count: 85),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "tool_a",
          description: "desc",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) { |_| "tool result payload" }

      hook_calls = [] of Tuple(Int32, Mantle::Clients::Response?)

      step = Mantle::Step.new(client, [tool])
      step.on_iteration = ->(msgs : Array(Mantle::Message), last_resp : Mantle::Clients::Response?) {
        hook_calls << {msgs.size, last_resp}
        msgs
      }

      caller_msgs = [Mantle::Message.new("user", "Start")]
      result = step.run(caller_msgs)

      result.ok?.should be_true
      result.value.should eq("Final answer")

      # Invoked exactly 2 times (pre-flight for iteration 1 and iteration 2, never post-response)
      hook_calls.size.should eq(2)

      # Iteration 1: last_response is nil, 1 message in working buffer (user)
      hook_calls[0][0].should eq(1)
      hook_calls[0][1].should be_nil

      # Iteration 2: last_response is iteration 1 response with prompt_eval_count 42, 3 messages (user, assistant, tool)
      hook_calls[1][0].should eq(3)
      hook_calls[1][1].not_nil!.prompt_eval_count.should eq(42)

      # Caller input unchanged
      caller_msgs.size.should eq(1)
      caller_msgs.first.content.should eq("Start")
    end

    it "uses the hook return value authoritatively for the next inference call" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_1",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "tool_a", arguments: %({}))
            ),
          ]
        ),
        Mantle::Clients::Response.new(content: "Answer", tool_calls: nil),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "tool_a",
          description: "desc",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) { |_| "huge verbose output that should be shed" }

      step = Mantle::Step.new(client, [tool])
      step.on_iteration = ->(msgs : Array(Mantle::Message), last_resp : Mantle::Clients::Response?) {
        # Rebuild using #map and keyword tool_call_id:
        msgs.map do |m|
          if m.role == "tool"
            Mantle::Message.new("tool", "[truncated 10 bytes]", tool_call_id: m.tool_call_id)
          else
            m
          end
        end
      }

      result = step.run([Mantle::Message.new("user", "Go")])
      result.ok?.should be_true

      # The second execute call received the truncated message
      client.recorded_messages.size.should eq(2)
      second_call_msgs = client.recorded_messages[1]
      tool_msg = second_call_msgs.find { |m| m.role == "tool" }
      tool_msg.should_not be_nil
      tool_msg.not_nil!.content.should eq("[truncated 10 bytes]")
      tool_msg.not_nil!.tool_call_id.should eq("call_1")
    end

    it "supports index write-back inside on_iteration" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_1",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(name: "tool_a", arguments: %({}))
            ),
          ]
        ),
        Mantle::Clients::Response.new(content: "Done", tool_calls: nil),
      ])

      tool = Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "tool_a",
          description: "desc",
          parameters: Mantle::Tools::ParametersSchema.new(properties: {} of String => Mantle::Tools::PropertyDefinition)
        )
      ) { |_| "original tool result" }

      step = Mantle::Step.new(client, [tool])
      step.on_iteration = ->(msgs : Array(Mantle::Message), _last_resp : Mantle::Clients::Response?) {
        msgs.each_with_index do |m, i|
          if m.role == "tool"
            # Explicit index write-back
            msgs[i] = Mantle::Message.new("tool", "rewritten via write-back", tool_call_id: m.tool_call_id)
          end
        end
        msgs
      }

      result = step.run([Mantle::Message.new("user", "Go")])
      result.ok?.should be_true

      tool_msg = client.recorded_messages[1].find { |m| m.role == "tool" }.not_nil!
      tool_msg.content.should eq("rewritten via write-back")
    end

    it "propagates exceptions raised in the hook immediately" do
      client = StepMockClient.new([
        Mantle::Clients::Response.new(content: "Never reached", tool_calls: nil),
      ])

      step = Mantle::Step.new(client)
      step.on_iteration = ->(_msgs : Array(Mantle::Message), _last_resp : Mantle::Clients::Response?) {
        raise ArgumentError.new("Cooperative interrupt requested")
      }

      expect_raises(ArgumentError, "Cooperative interrupt requested") do
        step.run([Mantle::Message.new("user", "Hello")])
      end
    end
  end
end
