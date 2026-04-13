require "./spec_helper"
require "../src/mantle/flow"
require "../src/mantle/tools"
require "../src/mantle/builtin_tools"
require "../src/mantle/tool_executor"
require "../src/mantle/tool_formatter"

# Mock client that simulates tool calling behavior
class ToolCallMockClient < Mantle::Client
  property responses : Array(Mantle::Response)
  property call_count : Int32 = 0

  def initialize(@responses : Array(Mantle::Response))
  end

  def execute(messages : Array(Hash(String, String)), tools : Array(Mantle::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Response
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

describe "Mantle ToolEnabledChatFlow" do
  describe "basic functionality without tools" do
    it "works like regular ChatFlow when no tools provided" do
      context_store = DummyContextStore.new
      context_manager = DummyContextManager.new(context_store)
      logger = DummyLogger.new

      # Client returns simple text response
      client = ToolCallMockClient.new([
        Mantle::Response.new(content: "Hello!", tool_calls: nil),
      ])

      flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

      response_received = nil
      flow.run(
        "Hi",
        on_response: ->(r : Mantle::Response) { response_received = r.content.not_nil! }
      )

      response_received.should eq("Hello!")
      client.call_count.should eq(1)
    end
  end

  describe "tool calling loop" do
    it "detects tool call, executes it, and continues until text response" do
      context_store = DummyContextStore.new
      context_manager = DummyContextManager.new(context_store)
      logger = DummyLogger.new

      # Simulate: LLM calls tool, then responds with text
      client = ToolCallMockClient.new([
        # First response: tool call
        Mantle::Response.new(
          content: nil,
          tool_calls: [
            Mantle::ToolCall.new(
              id: "call_1",
              type: "function",
              function: Mantle::ToolCallFunction.new(
                name: "get_time",
                arguments: "{}"
              )
            ),
          ]
        ),
        # Second response: text (after tool result)
        Mantle::Response.new(
          content: "The time is 12:00",
          tool_calls: nil
        ),
      ])

      # Custom tool callback
      tool_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        %({"time":"12:00"})
      }

      custom_tools = [
        Mantle::Tool.new(
          function: Mantle::FunctionDefinition.new(
            name: "get_time",
            description: "Get current time",
            parameters: Mantle::ParametersSchema.new(
              properties: {} of String => Mantle::PropertyDefinition
            )
          )
        ),
      ]

      flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

      final_response = nil
      flow.run(
        "What time is it?",
        custom_tools: custom_tools,
        tool_callback: tool_callback,
        on_response: ->(r : Mantle::Response) { final_response = r.content.not_nil! }
      )

      final_response.should eq("The time is 12:00")
      client.call_count.should eq(2) # Initial call + one continuation
    end

    it "enforces max_iterations limit" do
      context_store = DummyContextStore.new
      context_manager = DummyContextManager.new(context_store)
      logger = DummyLogger.new

      # Client always returns tool calls (infinite loop scenario)
      tool_call_response = Mantle::Response.new(
        content: nil,
        tool_calls: [
          Mantle::ToolCall.new(
            id: "call_loop",
            type: "function",
            function: Mantle::ToolCallFunction.new(
              name: "loop_tool",
              arguments: "{}"
            )
          ),
        ]
      )

      responses = Array(Mantle::Response).new(3, tool_call_response)
      responses << Mantle::Response.new(content: "Final text response after limit", tool_calls: nil)
      client = ToolCallMockClient.new(responses)

      tool_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        %({"result":"looping"})
      }

      custom_tools = [
        Mantle::Tool.new(
          function: Mantle::FunctionDefinition.new(
            name: "loop_tool",
            description: "A tool",
            parameters: Mantle::ParametersSchema.new(
              properties: {} of String => Mantle::PropertyDefinition
            )
          )
        ),
      ]

      flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

      final_response = nil
      flow.run(
        "Loop forever",
        custom_tools: custom_tools,
        tool_callback: tool_callback,
        max_iterations: 3,
        on_response: ->(r : Mantle::Response) { final_response = r.content.not_nil! }
      )

      final_response.should eq("Final text response after limit")
      client.call_count.should eq(4) # 3 tool calls + 1 final text call
    end
  end

  describe "built-in tools" do
    it "uses built-in read_file tool" do
      # Setup temp file
      temp_file = "/tmp/test_#{Time.utc.to_unix_ms}.txt"
      File.write(temp_file, "File contents")

      begin
        context_store = DummyContextStore.new
        context_manager = DummyContextManager.new(context_store)
        logger = DummyLogger.new

        client = ToolCallMockClient.new([
          Mantle::Response.new(
            content: nil,
            tool_calls: [
              Mantle::ToolCall.new(
                id: "call_read",
                type: "function",
                function: Mantle::ToolCallFunction.new(
                  name: "read_file",
                  arguments: %({"file_path":"#{temp_file}"})
                )
              ),
            ]
          ),
          Mantle::Response.new(content: "Got it!", tool_calls: nil),
        ])

        builtin_config = Mantle::BuiltinToolConfig.new(
          working_directory: "/tmp",
          allowed_paths: ["/tmp"]
        )

        flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

        final_response = nil
        flow.run(
          "Read the file",
          builtins: [Mantle::BuiltinTool::ReadFile],
          builtin_config: builtin_config,
          on_response: ->(r : Mantle::Response) { final_response = r.content.not_nil! }
        )

        final_response.should eq("Got it!")

        # Check that tool result was added to context with 'tool' role
        context_messages = context_store.messages
        tool_messages = context_messages.select { |m| m["role"] == "tool" }
        tool_messages.should_not be_empty
        # Tool result should contain the file content
        tool_messages[0]["content"].should contain("File contents")
      ensure
        File.delete(temp_file) if File.exists?(temp_file)
      end
    end
  end

  describe "mixed built-in and custom tools" do
    it "handles both types in single conversation" do
      temp_file = "/tmp/test_mixed_#{Time.utc.to_unix_ms}.txt"
      File.write(temp_file, "Data")

      begin
        context_store = DummyContextStore.new
        context_manager = DummyContextManager.new(context_store)
        logger = DummyLogger.new

        client = ToolCallMockClient.new([
          # Call built-in tool
          Mantle::Response.new(
            content: nil,
            tool_calls: [
              Mantle::ToolCall.new(
                id: "call_builtin",
                type: "function",
                function: Mantle::ToolCallFunction.new(
                  name: "read_file",
                  arguments: %({"file_path":"#{temp_file}"})
                )
              ),
            ]
          ),
          # Call custom tool
          Mantle::Response.new(
            content: nil,
            tool_calls: [
              Mantle::ToolCall.new(
                id: "call_custom",
                type: "function",
                function: Mantle::ToolCallFunction.new(
                  name: "process_data",
                  arguments: %({"data":"Data"})
                )
              ),
            ]
          ),
          # Final response
          Mantle::Response.new(content: "Processed!", tool_calls: nil),
        ])

        tool_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
          %({"result":"processed"})
        }

        custom_tools = [
          Mantle::Tool.new(
            function: Mantle::FunctionDefinition.new(
              name: "process_data",
              description: "Process data",
              parameters: Mantle::ParametersSchema.new(
                properties: {
                  "data" => Mantle::PropertyDefinition.new("string", "Data to process"),
                }
              )
            )
          ),
        ]

        builtin_config = Mantle::BuiltinToolConfig.new(
          working_directory: "/tmp",
          allowed_paths: ["/tmp"]
        )

        flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

        final_response = nil
        flow.run(
          "Read and process",
          builtins: [Mantle::BuiltinTool::ReadFile],
          custom_tools: custom_tools,
          tool_callback: tool_callback,
          builtin_config: builtin_config,
          on_response: ->(r : Mantle::Response) { final_response = r.content.not_nil! }
        )

        final_response.should eq("Processed!")
        client.call_count.should eq(3)
      ensure
        File.delete(temp_file) if File.exists?(temp_file)
      end
    end
  end
end
