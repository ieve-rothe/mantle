# mantle/client.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "http/headers"
require "http/client"
require "json"
require "random/secure"
require "../tools/tools"
require "../support/text"

module Mantle::Clients
  # Represents the configuration options for an LLM client.
  #
  # Holds configuration fields such as *model_name*, *stream*, *temperature*, *top_p*, *max_tokens*, *api_url*, and *keep_alive*.
  record ModelConfig, model_name : String, stream : Bool, temperature : Float64, top_p : Float64, max_tokens : Int32, api_url : String, keep_alive : Int32 | String = "10m"

  # Represents a function call within a tool call.
  #
  # Contains the function name and its arguments serialized as a JSON string.
  class ToolCallFunction
    include JSON::Serializable

    # Represents the name of the function to be called.
    property name : String

    # Represents the JSON string of arguments.
    #
    # normalized automatically via `ArgumentsConverter` from either OpenAI's string format or Ollama's object format.
    @[JSON::Field(converter: Mantle::Clients::ToolCallFunction::ArgumentsConverter)]
    property arguments : String

    # Creates a tool call function with the specified *name* and *arguments*.
    def initialize(@name : String, @arguments : String)
    end

    # :nodoc:
    module ArgumentsConverter
      def self.from_json(pull : JSON::PullParser) : String
        case pull.kind
        when .string?
          pull.read_string
        when .begin_object?
          JSON.parse(pull.read_raw).to_json
        else
          raise JSON::ParseException.new("Expected String or Object for arguments", pull.line_number, pull.column_number)
        end
      end

      def self.to_json(value : String, builder : JSON::Builder)
        JSON.parse(value).to_json(builder)
      end
    end
  end

  # Represents a tool call requested by the LLM.
  #
  # When the LLM decides to invoke a tool, it returns this structure.
  class ToolCall
    include JSON::Serializable

    # Represents the unique identifier for this tool call.
    property id : String

    # Represents the type of the tool.
    #
    # Defaults to `"function"` for function tools.
    @[JSON::Field(emit_null: false)]
    property type : String = "function"

    # Represents the function detail to call.
    property function : ToolCallFunction

    # Creates a tool call with the specified *id*, *function*, and *type*.
    def initialize(@id : String, @function : ToolCallFunction, @type : String = "function")
    end
  end

  # Represents the response from the LLM.
  #
  # A response can contain text content, a thinking process, tool calls, or a combination thereof.
  class Response
    include JSON::Serializable

    # Represents the text response content (if any).
    @[JSON::Field(emit_null: false)]
    property content : String?

    # Represents the thinking process output (if any).
    @[JSON::Field(emit_null: false)]
    property thinking : String?

    # Represents the list of tool calls requested by the LLM (if any).
    @[JSON::Field(emit_null: false)]
    property tool_calls : Array(ToolCall)?

    # Represents the reason inference finished (e.g. "stop", "length").
    @[JSON::Field(emit_null: false)]
    property done_reason : String?

    # Represents the number of tokens evaluated in the prompt (if provided).
    @[JSON::Field(emit_null: false)]
    property prompt_eval_count : Int32?

    # Represents the number of tokens generated in the evaluation (if provided).
    @[JSON::Field(emit_null: false)]
    property eval_count : Int32?

    # Represents the raw request payload sent to the LLM.
    @[JSON::Field(ignore: true)]
    property raw_request : String?

    # Represents the raw response payload returned from the LLM.
    @[JSON::Field(ignore: true)]
    property raw_response : String?

    # Creates an LLM response containing *content*, *tool_calls*, optional *thinking*, and completion metadata.
    def initialize(
      @content : String?,
      @tool_calls : Array(ToolCall)?,
      @thinking : String? = nil,
      @done_reason : String? = nil,
      @prompt_eval_count : Int32? = nil,
      @eval_count : Int32? = nil
    )
      if (raw = @content) && raw.includes?("<think>")
        clean, extracted = Mantle::Support::Text.extract_thinking(raw)
        @content = clean.empty? ? nil : clean
        @thinking ||= extracted
      end
    end

    # Returns true if generation was stopped because it hit the maximum token limit.
    def truncated? : Bool
      @done_reason == "length"
    end

    # Returns true if the response only contains thinking tokens with no final content or tool calls.
    def thinking_only? : Bool
      @content.nil? && (@tool_calls.nil? || @tool_calls.not_nil!.empty?) && !@thinking.nil?
    end

    # Returns true if the model exhausted its token limit or finished during the thinking phase without emitting content or tool calls.
    def truncated_in_thinking? : Bool
      thinking_only? && (truncated? || @content.nil?)
    end
  end

  # Represents the abstract base client for executing LLM requests.
  #
  # Implementations must define the `#execute` method to handle LLM calls.
  abstract class Client
    # Executes the LLM request with the provided *messages* and *tools*, yielding chunks to *on_chunk*.
    #
    # Returns a `Response`.
    abstract def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Response

    # Executes the LLM request without streaming, discarding partial chunks.
    #
    # Returns a `Response`.
    def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil) : Response
      execute(messages, tools) { |chunk| }
    end

    # Returns the temperature for this client.
    #
    # Subclasses should override this to expose their temperature setting.
    # Default returns 1.0 for clients that do not support temperature control.
    def temperature : Float64
      1.0
    end

    # Sets the temperature for this client.
    #
    # Subclasses should override this to expose their temperature setting.
    # Default is a no-op for clients that do not support temperature control.
    def temperature=(value : Float64)
    end
  end

  # Represents a client for sending inference requests to the Ollama API.
  class OllamaClient < Client
    # Represents the model identifier.
    property model_name : String

    # Represents whether response chunks should be streamed.
    property stream : Bool

    # Represents the temperature setting for controlling response randomness.
    property temperature : Float64

    # Represents the top-p setting for controlling response nucleus sampling.
    property top_p : Float64

    # Represents the maximum number of tokens to predict.
    property max_tokens : Int32

    # Represents the target API URL endpoint.
    property api_url : String

    # Represents the connection keep-alive duration.
    property keep_alive : Int32 | String

    # Creates an Ollama API client using the specified *model_config*.
    def initialize(model_config : ModelConfig)
      @model_name = model_config.model_name
      @stream = model_config.stream
      @temperature = model_config.temperature
      @top_p = model_config.top_p
      @max_tokens = model_config.max_tokens
      @api_url = model_config.api_url
      @keep_alive = model_config.keep_alive
    end

    def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Response
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }

      body = build_request_body(messages, tools)

      if @stream
        execute_stream(headers, body, &on_chunk)
      else
        execute_standard(headers, body, &on_chunk)
      end
    end

    # Mantle::Tools::Tool is the canonical internal tool schema.
    # Provider adapters map canonical tools to provider-specific wire schemas.
    # Ollama natively expects OpenAI-compatible function tool definitions.
    private def format_tools(tools : Array(Mantle::Tools::Tool))
      tools
    end

    private def build_request_body(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)?) : String
      base_options = {
        model:      @model_name,
        messages:   messages,
        stream:     @stream,
        keep_alive: @keep_alive,
        options:    {
          num_predict: @max_tokens,
          temperature: @temperature,
          top_p:       @top_p,
        },
      }

      if tools
        base_options.merge({tools: format_tools(tools)}).to_json
      else
        base_options.to_json
      end
    end

    private def execute_stream(headers : HTTP::Headers, body : String, &on_chunk : String -> Nil) : Response
      full_content = String::Builder.new
      full_thinking = String::Builder.new
      tool_calls_json = nil
      done_reason : String? = nil
      prompt_eval_count : Int32? = nil
      eval_count : Int32? = nil
      raw_response_builder = String::Builder.new
      status_code = 0
      error_body = ""

      HTTP::Client.post(@api_url, headers: headers, body: body) do |response|
        status_code = response.status_code
        if response.status.success?
          if io = response.body_io
            io.each_line do |line|
              next if line.empty?
              raw_response_builder.puts(line)

              parsed = JSON.parse(line)
              msg = parsed["message"]?

              if msg
                if chunk = msg["content"]?.try(&.as_s?)
                  unless chunk.empty?
                    on_chunk.call(chunk)
                    full_content << chunk
                  end
                end

                if chunk = msg["thinking"]?.try(&.as_s?)
                  unless chunk.empty?
                    full_thinking << chunk
                  end
                end

                if tc = msg["tool_calls"]?
                  tool_calls_json = tc
                end
              end

              if dr = parsed["done_reason"]?.try(&.as_s?)
                done_reason = dr
              end

              if pec = parse_token_count(parsed["prompt_eval_count"]?)
                prompt_eval_count = pec
              end

              if ec = parse_token_count(parsed["eval_count"]?)
                eval_count = ec
              end
            end
          end
        else
          error_body = response.body_io ? response.body_io.gets_to_end : ""
        end
      end

      if status_code >= 200 && status_code < 300
        build_response(
          raw_content: full_content.empty? ? nil : full_content.to_s,
          api_thinking: full_thinking.empty? ? nil : full_thinking.to_s,
          tool_calls_json: tool_calls_json,
          done_reason: done_reason,
          prompt_eval_count: prompt_eval_count,
          eval_count: eval_count,
          raw_request: body,
          raw_response: raw_response_builder.to_s
        )
      else
        raise Exception.new("Error #{status_code}: #{error_body}")
      end
    end

    private def execute_standard(headers : HTTP::Headers, body : String, &on_chunk : String -> Nil) : Response
      response = HTTP::Client.post(@api_url, headers: headers, body: body)

      if response.status.success?
        response_data = JSON.parse(response.body)
        message = response_data["message"]?

        resp = build_response(
          raw_content: message ? message["content"]?.try(&.as_s?) : nil,
          api_thinking: message ? message["thinking"]?.try(&.as_s?) : nil,
          tool_calls_json: message ? message["tool_calls"]? : nil,
          done_reason: response_data["done_reason"]?.try(&.as_s?),
          prompt_eval_count: parse_token_count(response_data["prompt_eval_count"]?),
          eval_count: parse_token_count(response_data["eval_count"]?),
          raw_request: body,
          raw_response: response.body
        )

        if content = resp.content
          on_chunk.call(content) unless content.empty?
        end

        resp
      else
        raise Exception.new("Error #{response.status_code}: #{response.body}")
      end
    end

    private def build_response(
      raw_content : String?,
      api_thinking : String?,
      tool_calls_json : JSON::Any?,
      done_reason : String?,
      prompt_eval_count : Int32?,
      eval_count : Int32?,
      raw_request : String,
      raw_response : String
    ) : Response
      clean_content, extracted_thinking = if raw_content && !raw_content.empty?
        Mantle::Support::Text.extract_thinking(raw_content)
      else
        {nil, nil}
      end

      final_content = (clean_content && !clean_content.empty?) ? clean_content : nil
      final_thinking = (api_thinking && !api_thinking.empty?) ? api_thinking : extracted_thinking
      tool_calls = parse_tool_calls(tool_calls_json)

      resp = Response.new(
        content: final_content,
        tool_calls: tool_calls,
        thinking: final_thinking,
        done_reason: done_reason,
        prompt_eval_count: prompt_eval_count,
        eval_count: eval_count
      ).tap do |r|
        r.raw_request = raw_request
        r.raw_response = raw_response
      end

      if resp.truncated_in_thinking?
        Mantle::Log.warn {
          "LLM generation was truncated during the thinking phase (hit max_tokens limit #{@max_tokens} before generating any content or tool calls). Consider increasing max_tokens or disabling thinking."
        }
      end

      resp
    end

    private def parse_token_count(value : JSON::Any?) : Int32?
      return nil unless value
      value.as_i? || value.as_i64?.try(&.to_i32)
    end

    private def parse_tool_calls(tool_calls_json : JSON::Any?) : Array(ToolCall)?
      return nil unless tool_calls_json

      arr_json = tool_calls_json.as_a
      arr_json.each do |t|
        if !t.as_h.has_key?("id")
          t.as_h["id"] = JSON::Any.new("call_" + Random::Secure.hex(4))
        end
      end
      Array(ToolCall).from_json(arr_json.to_json)
    end
  end
end
