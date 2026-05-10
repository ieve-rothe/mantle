require "benchmark"
require "../src/mantle/tool_formatter"
require "../src/mantle/client"

module Mantle
  module ToolFormatter
    def self.original_format_tool_call(tool_call : ToolCall) : String
      function_name = tool_call.function.name
      arguments = tool_call.function.arguments

      # Parse arguments JSON
      begin
        args_json = JSON.parse(arguments)

        if args_json.as_h.empty?
          "Called #{function_name}()"
        else
          # Format arguments as key: value pairs
          args_str = args_json.as_h.map do |key, value|
            "#{key}: #{format_json_value(value)}"
          end.join(", ")

          "Called #{function_name}(#{args_str})"
        end
      rescue
        # If JSON parsing fails, show raw arguments
        "Called #{function_name}(#{arguments})"
      end
    end

    def self.optimized_format_tool_call(tool_call : ToolCall) : String
      function_name = tool_call.function.name
      arguments = tool_call.function.arguments

      # Parse arguments JSON
      begin
        args_json = JSON.parse(arguments)
        args_h = args_json.as_h

        String.build do |io|
          io << "Called " << function_name << "("
          args_h.each_with_index do |(key, value), i|
            io << ", " if i > 0
            io << key << ": "
            format_json_value_to_io(value, io)
          end
          io << ")"
        end
      rescue
        # If JSON parsing fails, show raw arguments
        String.build do |io|
          io << "Called " << function_name << "(" << arguments << ")"
        end
      end
    end

    private def self.format_json_value_to_io(value : JSON::Any, io : IO) : Nil
      case raw = value.raw
      when String
        io << '"' << raw << '"'
      when Bool, Int64, Float64
        raw.to_s(io)
      else
        value.to_json(io)
      end
    end
  end
end

# Create a sample tool call with many arguments
args = {} of String => String
20.times do |i|
  args["arg#{i}"] = "value#{i}"
end
tool_call = Mantle::ToolCall.new(
  id: "call_123",
  function: Mantle::ToolCallFunction.new(
    name: "test_function",
    arguments: args.to_json
  )
)

puts "Benchmarking ToolFormatter.format_tool_call"
Benchmark.ips do |x|
  x.report("original") do
    Mantle::ToolFormatter.original_format_tool_call(tool_call)
  end

  x.report("optimized") do
    Mantle::ToolFormatter.optimized_format_tool_call(tool_call)
  end
end
