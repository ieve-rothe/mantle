# mantle/client.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "http/headers"
require "http/client"
require "json"
require "./tools"

module Mantle
  # Record is a macro that expands to define struct with initializer, getters and a copy_with and clone helper methods.
  # Reminder that it's positional, not named arguments
  record ModelConfig, model_name : String, stream : Bool, temperature : Float64, top_p : Float64, max_tokens : Int32, api_url : String

  # Represents a function call within a tool call
  # Contains the function name and its arguments as a JSON string
  class ToolCallFunction
    include JSON::Serializable

    property name : String # Function name (e.g., "read_file")

    # Custom converter to handle both string and object formats for arguments
    # OpenAI format: arguments as JSON string
    # Ollama format: arguments as JSON object
    @[JSON::Field(converter: Mantle::ToolCallFunction::ArgumentsConverter)]
    property arguments : String # JSON string of arguments (normalized)

    def initialize(@name : String, @arguments : String)
    end

    # Custom JSON converter that handles both string and object argument formats
    module ArgumentsConverter
      def self.from_json(pull : JSON::PullParser) : String
        case pull.kind
        when .string?
          # OpenAI format: already a JSON string
          pull.read_string
        when .begin_object?
          # Ollama format: JSON object, convert to string
          JSON.parse(pull.read_raw).to_json
        else
          raise JSON::ParseException.new("Expected String or Object for arguments", pull.line_number, pull.column_number)
        end
      end

      def self.to_json(value : String, builder : JSON::Builder)
        builder.string(value)
      end
    end
  end

  # Represents a tool call from the LLM
  # When the LLM wants to invoke a tool, it returns this structure
  class ToolCall
    include JSON::Serializable

    property id : String # Unique identifier for this tool call

    # Type field defaults to "function" since some APIs (e.g., Ollama) omit it
    @[JSON::Field(emit_null: false)]
    property type : String = "function" # Always "function" for function tools

    property function : ToolCallFunction # The function to call

    def initialize(@id : String, @function : ToolCallFunction, @type : String = "function")
    end
  end

  # Response from the LLM, can contain text content, tool calls, or both
  # Replaces the simple String return type to support tool calling
  class Response
    include JSON::Serializable

    @[JSON::Field(emit_null: false)]
    property content : String? # Text response content (if any)

    @[JSON::Field(emit_null: false)]
    property tool_calls : Array(ToolCall)? # Tool calls requested (if any)

    @[JSON::Field(ignore: true)]
    property raw_request : String?

    @[JSON::Field(ignore: true)]
    property raw_response : String?

    def initialize(@content : String?, @tool_calls : Array(ToolCall)?)
    end
  end

  # Contract for Client class. Using a contract to allow for a dummy client class when unit testing other parts of codebase.
  # Now returns Response instead of String to support tool calling
  abstract class Client
    abstract def execute(messages : Array(Hash(String, String)), tools : Array(Tool)? = nil) : Response
  end

  # Client for sending requests to ollama API
  class LlamaClient < Client
    property model_name : String
    property stream : Bool
    property temperature : Float64
    property top_p : Float64
    property max_tokens : Int32
    property api_url : String

    def initialize(model_config : ModelConfig)
      @model_name = model_config.model_name
      @stream = model_config.stream
      @temperature = model_config.temperature
      @top_p = model_config.top_p
      @max_tokens = model_config.max_tokens
      @api_url = model_config.api_url
    end

    def execute(messages : Array(Hash(String, String)), tools : Array(Tool)? = nil) : Response
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }

      # Build payload conditionally based on whether tools are provided
      body = if tools
               {
                 model:    @model_name,
                 messages: messages,
                 stream:   @stream,
                 tools:    tools,
                 options:  {
                   num_predict: @max_tokens,
                   temperature: @temperature,
                   top_p:       @top_p,
                 },
               }.to_json
             else
               {
                 model:    @model_name,
                 messages: messages,
                 stream:   @stream,
                 options:  {
                   num_predict: @max_tokens,
                   temperature: @temperature,
                   top_p:       @top_p,
                 },
               }.to_json
             end

      response = HTTP::Client.post(@api_url, headers: headers, body: body)

      if response.status.success?
        response_data = JSON.parse(response.body)
        message = response_data["message"]

        # Extract content (may be nil if only tool_calls present)
        content = message["content"]?.try(&.as_s?)

        # Extract tool_calls if present
        tool_calls_json = message["tool_calls"]?
        tool_calls = if tool_calls_json
                       Array(ToolCall).from_json(tool_calls_json.to_json)
                     else
                       nil
                     end

        return Response.new(content: content, tool_calls: tool_calls).tap do |r|
          r.raw_request = body
          r.raw_response = response.body
        end
      else
        raise Exception.new("Error #{response.status_code}: #{response.body}")
      end
    end
  end
end
