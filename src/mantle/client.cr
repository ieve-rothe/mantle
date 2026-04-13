# mantle/client.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "http/headers"
require "http/client"
require "json"
require "random/secure"
require "./tools"

module Mantle
  # Record is a macro that expands to define struct with initializer, getters and a copy_with and clone helper methods.
  # Reminder that it's positional, not named arguments
  record ModelConfig, model_name : String, stream : Bool, temperature : Float64, top_p : Float64, max_tokens : Int32, api_url : String, keep_alive : Int32 | String = "10m"

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
    property thinking : String? # Thinking process output (if any)

    @[JSON::Field(emit_null: false)]
    property tool_calls : Array(ToolCall)? # Tool calls requested (if any)

    @[JSON::Field(ignore: true)]
    property raw_request : String?

    @[JSON::Field(ignore: true)]
    property raw_response : String?

    def initialize(@content : String?, @tool_calls : Array(ToolCall)?, @thinking : String? = nil)
    end
  end

  # Contract for Client class. Using a contract to allow for a dummy client class when unit testing other parts of codebase.
  # Now returns Response instead of String to support tool calling
  abstract class Client
    # Accepts an optional block (the `&on_chunk` part) which lets consumer apps
    # "listen" to pieces of the response as they arrive (like a typewriter effect)
    abstract def execute(messages : Array(Hash(String, String)), tools : Array(Tool)? = nil, &on_chunk : String -> Nil) : Response

    # A fallback version of `execute` for apps that don't want to deal with streaming.
    # It just runs the request and throws away the partial chunks, waiting for the final response.
    def execute(messages : Array(Hash(String, String)), tools : Array(Tool)? = nil) : Response
      execute(messages, tools) { |chunk| }
    end
  end

  # Client for sending requests to ollama API
  class LlamaClient < Client
    property model_name : String
    property stream : Bool
    property temperature : Float64
    property top_p : Float64
    property max_tokens : Int32
    property api_url : String
    property keep_alive : Int32 | String

    def initialize(model_config : ModelConfig)
      @model_name = model_config.model_name
      @stream = model_config.stream
      @temperature = model_config.temperature
      @top_p = model_config.top_p
      @max_tokens = model_config.max_tokens
      @api_url = model_config.api_url
      @keep_alive = model_config.keep_alive
    end

    def execute(messages : Array(Hash(String, String)), tools : Array(Tool)? = nil, &on_chunk : String -> Nil) : Response
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }

      # Build payload conditionally based on whether tools are provided
      body = if tools
               {
                 model:      @model_name,
                 messages:   messages,
                 stream:     @stream,
                 tools:      tools,
                 keep_alive: @keep_alive,
                 options:    {
                   num_predict: @max_tokens,
                   temperature: @temperature,
                   top_p:       @top_p,
                 },
               }.to_json
             else
               {
                 model:      @model_name,
                 messages:   messages,
                 stream:     @stream,
                 keep_alive: @keep_alive,
                 options:    {
                   num_predict: @max_tokens,
                   temperature: @temperature,
                   top_p:       @top_p,
                 },
               }.to_json
             end

      if @stream
        full_content = String::Builder.new
        full_thinking = String::Builder.new
        tool_calls_json = nil
        raw_response_builder = String::Builder.new
        status_code = 0
        error_body = ""

        # By passing a `do |response|` block to `.post`, Crystal gives us a live data stream
        # (`body_io`) instead of waiting for the whole download to finish.
        HTTP::Client.post(@api_url, headers: headers, body: body) do |response|
          status_code = response.status_code
          if response.status.success?
            if io = response.body_io
              # Read the stream line-by-line as data arrives from Ollama.
              # Ollama streams its responses as NDJSON (Newline Delimited JSON).
              io.each_line do |line|
                next if line.empty?
                raw_response_builder.puts(line)

                parsed = JSON.parse(line)
                msg = parsed["message"]

                # As soon as we get a text chunk, tell the app about it right away!
                if chunk = msg["content"]?.try(&.as_s?)
                  unless chunk.empty?
                    on_chunk.call(chunk)
                    full_content << chunk
                  end
                end

                # Record thinking tags if present
                if chunk = msg["thinking"]?.try(&.as_s?)
                  unless chunk.empty?
                    full_thinking << chunk
                  end
                end

                # If the AI wants to use a tool, save it for later.
                # (Tools don't need to be streamed to the user letter-by-letter).
                if tc = msg["tool_calls"]?
                  tool_calls_json = tc
                end
              end
            end
          else
            error_body = response.body_io ? response.body_io.gets_to_end : ""
          end
        end

        if status_code >= 200 && status_code < 300
          tool_calls = if tool_calls_json
                         # Some versions of Ollama forget to assign a unique ID to their tool calls.
                         # We'll just generate our own random ID to prevent the app from crashing.
                         arr_json = tool_calls_json.as_a
                         arr_json.each do |t|
                           if !t.as_h.has_key?("id")
                             t.as_h["id"] = JSON::Any.new("call_" + Random::Secure.hex(4))
                           end
                         end
                         Array(ToolCall).from_json(arr_json.to_json)
                       else
                         nil
                       end

          final_content = full_content.empty? ? nil : full_content.to_s
          final_thinking = full_thinking.empty? ? nil : full_thinking.to_s

          # Return the final stitched-together response at the very end
          return Response.new(content: final_content, tool_calls: tool_calls, thinking: final_thinking).tap do |r|
            r.raw_request = body
            r.raw_response = raw_response_builder.to_s
          end
        else
          raise Exception.new("Error #{status_code}: #{error_body}")
        end
      else
        response = HTTP::Client.post(@api_url, headers: headers, body: body)

        if response.status.success?
          response_data = JSON.parse(response.body)
          message = response_data["message"]

          # Extract content (may be nil if only tool_calls present)
          content = message["content"]?.try(&.as_s?)

          if content && !content.empty?
            on_chunk.call(content)
          end

          # Extract thinking process (if any)
          thinking = message["thinking"]?.try(&.as_s?)

          # Extract tool_calls if present
          tool_calls_json = message["tool_calls"]?
          tool_calls = if tool_calls_json
                         # Ollama sometimes omits ID, inject one if missing
                         arr_json = tool_calls_json.as_a
                         arr_json.each do |t|
                           if !t.as_h.has_key?("id")
                             t.as_h["id"] = JSON::Any.new("call_" + Random::Secure.hex(4))
                           end
                         end
                         Array(ToolCall).from_json(arr_json.to_json)
                       else
                         nil
                       end

          return Response.new(content: content, tool_calls: tool_calls, thinking: thinking).tap do |r|
            r.raw_request = body
            r.raw_response = response.body
          end
        else
          raise Exception.new("Error #{response.status_code}: #{response.body}")
        end
      end
    end
  end
end
