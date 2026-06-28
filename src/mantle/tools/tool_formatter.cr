# mantle/tool_formatter.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../clients/client"
require "json"

module Mantle::Tools
  # Formats tool calls and results as natural language for context storage.
  #
  # Converts structured tool interactions into human-readable text.
  module ToolFormatter
    # Represents the maximum length of a formatted tool result before it gets truncated.
    MAX_RESULT_LENGTH = 500

    # Formats a single *tool_call* as natural language.
    #
    # ```
    # # Example output format:
    # "Called read_file(file_path: \"test.txt\")"
    # ```
    def self.format_tool_call(tool_call : Mantle::Clients::ToolCall) : String
      function_name = tool_call.function.name
      arguments = tool_call.function.arguments

      # Parse arguments JSON
      begin
        args_json = JSON.parse(arguments)
        args_h = args_json.as_h

        # Use String.build to efficiently construct the string without creating
        # many small intermediate pieces in memory.
        String.build do |io|
          io << "Called " << function_name << " (ID: " << tool_call.id << ") ("
          # We iterate through each argument and write it directly to the output buffer
          args_h.each_with_index do |(key, value), i|
            io << ", " if i > 0
            io << key << ": "
            format_json_value(value, io)
          end
          io << ")"
        end
      rescue
        # If JSON parsing fails, show raw arguments
        "Called #{function_name} (ID: #{tool_call.id}) (#{arguments})"
      end
    end

    # Formats a *tool_result* as natural language.
    #
    # If the *tool_result* has a `ToolResult#formatted_override`, that override is returned exactly.
    # Otherwise, it parses the JSON result to create a standard output string:
    #
    # ```
    # # Example default output:
    # "Result from call_123: Hello, World!"
    # ```
    def self.format_tool_result(tool_result : ToolResult) : String
      # If formatted_override is present, use it exactly as provided
      if formatted_override = tool_result.formatted_override
        return formatted_override
      end

      # Otherwise, use default formatting
      tool_call_id = tool_result.tool_call_id
      result = tool_result.result

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

    # Formats an assistant message containing *content* and *tool_calls*.
    #
    # Returns a natural language representation suitable for context storage.
    def self.format_assistant_message_with_tool_calls(content : String?, tool_calls : Array(Mantle::Clients::ToolCall)) : String
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

    # :nodoc:
    private def self.format_json_value(value : JSON::Any) : String
      String.build do |io|
        format_json_value(value, io)
      end
    end

    # :nodoc:
    private def self.format_json_value(value : JSON::Any, io : IO) : Nil
      case raw = value.raw
      when String
        io << '"' << raw << '"'
      when Bool, Int64, Float64
        raw.to_s(io)
      else
        value.to_json(io)
      end
    end

    # :nodoc:
    private def self.truncate_string(str : String, max_length : Int32) : String
      return str if str.size <= max_length

      # If max_length is too small to even hold ellipsis, just return a substring
      # or empty string if max_length is 0.
      if max_length <= 3
        return str[0, Math.max(0, max_length)]
      end

      str[0, max_length - 3] + "..."
    end
  end
end
