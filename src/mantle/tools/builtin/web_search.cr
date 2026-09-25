# mantle/tools/builtin/web_search.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../tools"
require "http/client"
require "json"

module Mantle::Tools::Builtin
  module WebSearch
    def self.definition : FunctionDefinition
      FunctionDefinition.new(
        name: "web_search",
        description: "Perform a real-time web search using the Tavily API to retrieve up-to-date information.",
        parameters: ParametersSchema.new(
          properties: {
            "query" => PropertyDefinition.new(
              type: "string",
              description: "The search query to perform"
            ),
            "search_depth" => PropertyDefinition.new(
              type: "string",
              description: "The depth of the search ('basic' or 'advanced')"
            ),
            "max_results" => PropertyDefinition.new(
              type: "integer",
              description: "The maximum number of search results to return"
            ),
          },
          required: ["query"]
        )
      )
    end

    def self.create(api_key : (String | Proc(String?))? = nil) : Tool
      Tool.new(definition) do |arguments|
        execute(arguments, api_key: api_key)
      end
    end

    def self.create(_sandbox : FileSystemSandbox) : Tool
      create
    end

    def self.resolve_api_key(custom_key : (String | Proc(String?))? = nil) : String?
      if custom_key.is_a?(Proc)
        if val = custom_key.call
          return val.strip unless val.strip.empty?
        end
      elsif custom_key.is_a?(String)
        return custom_key.strip unless custom_key.strip.empty?
      end

      if env_val = ENV["TAVILY_API_KEY"]? || ENV["TAVILY_KEY"]?
        return env_val.strip unless env_val.strip.empty?
      end

      # Check standard config file candidates
      home = Path.home.to_s
      xdg_config = ENV["XDG_CONFIG_HOME"]?
      config_home = (xdg_config && !xdg_config.empty?) ? xdg_config : File.join(home, ".config")

      candidates = [
        File.join(config_home, "nightmare", "keys", "tavily"),
        File.join(config_home, "nightmare", "tavily_key"),
        File.join(config_home, "mantle", "keys", "tavily"),
        File.join(config_home, "mantle", "tavily_key"),
      ]

      candidates.each do |candidate|
        if File.exists?(candidate)
          val = File.read(candidate).strip
          return val unless val.empty?
        end
      end

      nil
    end

    def self.execute(arguments : Hash(String, JSON::Any), api_key : (String | Proc(String?))? = nil) : String
      query = arguments["query"]?.try(&.as_s?)
      search_depth = arguments["search_depth"]?.try(&.as_s?) || "basic"
      max_results = arguments["max_results"]?.try(&.as_i?) || 5

      unless query
        return {success: false, error: "Missing required parameter: query"}.to_json
      end

      key = resolve_api_key(api_key)
      unless key && !key.empty?
        return {
          success: false,
          error:   "Missing Tavily API key in ENV (TAVILY_API_KEY) or ~/.config/nightmare/keys/tavily (or ~/.config/nightmare/tavily_key)",
        }.to_json
      end

      begin
        uri = URI.parse("https://api.tavily.com")
        client = HTTP::Client.new(uri)

        payload = {
          "api_key"      => key,
          "query"        => query,
          "search_depth" => search_depth,
          "max_results"  => max_results,
        }.to_json

        headers = HTTP::Headers.new
        headers["Content-Type"] = "application/json"
        headers["Authorization"] = "Bearer #{key}"
        response = client.post("/search", headers: headers, body: payload)

        if response.status_code == 200
          parsed = JSON.parse(response.body)
          results = parsed["results"]? || JSON::Any.new([] of JSON::Any)
          answer = parsed["answer"]?.try(&.as_s?)

          result_hash = {
            "success" => JSON::Any.new(true),
            "query"   => JSON::Any.new(parsed["query"]?.try(&.as_s?) || query),
            "results" => results,
          }
          if answer && !answer.empty?
            result_hash["answer"] = JSON::Any.new(answer)
          end

          result_hash.to_json
        else
          {
            success: false,
            error:   "Tavily API error: #{response.status_code} - #{response.body}",
          }.to_json
        end
      rescue ex
        {success: false, error: "Error performing web search: #{ex.message}"}.to_json
      end
    end
  end
end
