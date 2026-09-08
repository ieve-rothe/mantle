require "./integration_helper"

describe "Integration: Tool Loops" do
  it "successfully manages multiple chained tool calls returning a final answer" do
    context_file = "/tmp/integration_tool_loop_context_#{Time.utc.to_unix_ms}.json"
    File.delete(context_file) if File.exists?(context_file)

    begin
      context_store = Mantle::Storage::JSONContextStore.new("System prompt", context_file)
      context_manager = DummyContextManager.new(context_store)

      client = ScriptedClient.new([
        # Response 1: LLM decides to call "tool_A"
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_a1",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(
                name: "tool_A",
                arguments: %({"input":"start"})
              )
            ),
          ]
        ),
        # Response 2: LLM receives tool_A result, decides to call "tool_B"
        Mantle::Clients::Response.new(
          content: nil,
          tool_calls: [
            Mantle::Clients::ToolCall.new(
              id: "call_b1",
              type: "function",
              function: Mantle::Clients::ToolCallFunction.new(
                name: "tool_B",
                arguments: %({"input":"intermediate"})
              )
            ),
          ]
        ),
        # Response 3: LLM has enough information, returns text response
        Mantle::Clients::Response.new(content: "Final result based on tools", tool_calls: nil),
      ])

      custom_tools = [
        Mantle::Tools::Tool.new(
          function: Mantle::Tools::FunctionDefinition.new(
            name: "tool_A",
            description: "First tool",
            parameters: Mantle::Tools::ParametersSchema.new(
              properties: {
                "input" => Mantle::Tools::PropertyDefinition.new("string", "Input data"),
              }
            )
          )
        ),
        Mantle::Tools::Tool.new(
          function: Mantle::Tools::FunctionDefinition.new(
            name: "tool_B",
            description: "Second tool",
            parameters: Mantle::Tools::ParametersSchema.new(
              properties: {
                "input" => Mantle::Tools::PropertyDefinition.new("string", "Input data"),
              }
            )
          )
        ),
      ]

      tool_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
        case name
        when "tool_A"
          %({"result":"intermediate"})
        when "tool_B"
          %({"result":"final_data"})
        else
          %({"error":"unknown tool"})
        end
      }

      step = Mantle::Step.new(client, custom_tools, tool_callback: tool_callback)

      messages = [
        Mantle::Message.new("system", "System prompt"),
        Mantle::Message.new("user", "Please run your tools."),
      ]

      result = step.run(messages)

      # 1. Verify final text response is returned
      result.ok?.should be_true
      result.unwrap.should eq("Final result based on tools")

      # 2. Verify exact number of API calls made to the "LLM"
      client.call_count.should eq(3)
      result.iterations.should eq(3)
    ensure
      File.delete(context_file) if File.exists?(context_file)
    end
  end
end
