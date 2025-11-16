# mantle/client.cr

module Mantle
  # Record is a macro that expands to define struct with initializer, getters and a copy_with and clone helper methods.
  # Reminder that it's positional, not named arguments
  record ModelConfig, model_name : String, stream : Bool, temperature : Float64, top_p : Float64, max_tokens : Int32, api_url : String

  # Contract for Client class. Using a contract to allow for a dummy client class when unit testing other parts of codebase.
  abstract class Client
    abstract def execute(prompt : String) : String
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

    def execute(prompt : String) : String
      headers = HTTP::Headers{
        "Content-Type" => "application/json",
      }

      body = {
        model:       @model_name,
        prompt:      prompt,
        stream:      @stream,
        temperature: @temperature,
        top_p:       @top_p,
        max_tokens:  @max_tokens,
      }.to_json

      response = HTTP::Client.post(@api_url, headers: headers, body: body)

      if response.status.success?
        response_data = JSON.parse(response.body)
        generated_text = response_data["response"].as_s
        return generated_text
      else
        raise Exception.new("Error #{response.status_code}: #{response.body}")
      end
    end
  end
end
