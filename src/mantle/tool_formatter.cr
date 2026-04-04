require "./client"
require "json"

module Mantle
  # Formats tool calls and results as natural language for context storage
  # Converts structured tool interactions into human-readable text
  module ToolFormatter
    MAX_RESULT_LENGTH = 500

    # Format a single tool call as natural language
    # Example: "Called read_file(file_path: 'test.txt')"
    def self.format_tool_call(tool_call : ToolCall) : String
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

    # Format a tool result as natural language
    # Example: "Result from call_123: Hello, World!"
    def self.format_tool_result(tool_call_id : String, result : String) : String
      # Try to parse result JSON and extract relevant info
      begin
        result_json = JSON.parse(result)

        # Check for error
        if error = result_json["error"]?
          return "Result from #{tool_call_id}: Error - #{error}"
        end

        # Check for content or entries
        if content = result_json["content"]?
          content_str = content.to_s
          truncated = truncate_string(content_str, MAX_RESULT_LENGTH)
          return "Result from #{tool_call_id}: #{truncated}"
        elsif entries = result_json["entries"]?
          entries_str = entries.as_a.join(", ")
          truncated = truncate_string(entries_str, MAX_RESULT_LENGTH)
          return "Result from #{tool_call_id}: [#{truncated}]"
        elsif success = result_json["success"]?
          return "Result from #{tool_call_id}: Success"
        else
          # Generic result
          truncated = truncate_string(result, MAX_RESULT_LENGTH)
          return "Result from #{tool_call_id}: #{truncated}"
        end
      rescue
        # If JSON parsing fails, use raw result
        truncated = truncate_string(result, MAX_RESULT_LENGTH)
        "Result from #{tool_call_id}: #{truncated}"
      end
    end

    # Format assistant message that may contain content and/or tool calls
    # Returns natural language representation suitable for context storage
    def self.format_assistant_message_with_tool_calls(content : String?, tool_calls : Array(ToolCall)) : String
      parts = [] of String

      # Add content if present
      if content && !content.empty?
        parts << content
      end

      # Add formatted tool calls
      if tool_calls && !tool_calls.empty?
        tool_calls.each do |call|
          parts << format_tool_call(call)
        end
      end

      parts.join(" | ")
    end

    # Helper: Format a JSON::Any value for display
    private def self.format_json_value(value : JSON::Any) : String
      case value.raw
      when String
        %("#{value.as_s}")
      when Bool, Int64, Float64
        value.to_s
      else
        value.to_json
      end
    end

    # Helper: Truncate string to max length with ellipsis
    private def self.truncate_string(str : String, max_length : Int32) : String
      if str.size <= max_length
        str
      else
        str[0, max_length - 3] + "..."
      end
    end
  end
end
