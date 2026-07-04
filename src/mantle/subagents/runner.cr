require "./profile"
require "../clients/client"
require "../tools/tools"

module Mantle::Subagents
  # Runner for executing subagents with depth and token limits.
  class Runner
    # Available subagent profiles
    property profiles : Hash(String, Profile)

    # Reference to LLM client
    property client : Mantle::Clients::Client?

    # Maximum allowed subagent depth
    property max_depth : Int32

    # Maximum allowed token budget for interactive sessions
    property max_token_budget : Int32

    def initialize(
      @profiles : Hash(String, Profile) = {} of String => Profile,
      @client : Mantle::Clients::Client? = nil,
      @max_depth : Int32 = 1,
      @max_token_budget : Int32 = 100000
    )
    end

    # Spawns a subagent in single-turn mode.
    # Enforces max_depth by raising an error if depth > @max_depth.
    def spawn(
      profile_id : String,
      query : String,
      context : String = "",
      depth : Int32 = 1,
      call_id : String? = nil
    ) : String
      if depth > @max_depth
        raise "Subagent depth limit exceeded: #{depth} > #{@max_depth}"
      end

      profile = @profiles[profile_id]?
      unless profile
        available = @profiles.keys.join(", ")
        return "Error: Profile '#{profile_id}' not found. Available: #{available}"
      end

      client = @client
      unless client
        return "Error: No LLM client configured for subagents"
      end

      full_prompt = build_subagent_prompt(profile, query, context)

      begin
        orig_max_tokens = nil
        orig_temp = client.temperature

        if client.is_a?(Mantle::Clients::LlamaClient)
          orig_max_tokens = client.as(Mantle::Clients::LlamaClient).max_tokens
          client.as(Mantle::Clients::LlamaClient).max_tokens = profile.max_tokens
        end
        client.temperature = profile.temperature

        messages = [Mantle::Message.new(role: "user", content: full_prompt)]
        response = client.execute(messages)

        response_content = if (c = response.content) && !c.strip.empty?
                             if (t = response.thinking) && !t.strip.empty?
                               "🤔 [Thinking Process]\n#{t.strip}\n\n[Response]\n#{c.strip}"
                             else
                               c
                             end
                           else
                             response.thinking
                           end

        if response_content && !response_content.strip.empty?
          format_subagent_response(profile, response_content, call_id)
        else
          "Error spawning subagent '#{profile.name}': No response content returned"
        end
      rescue ex
        "Error spawning subagent '#{profile.name}': #{ex.message}"
      ensure
        if client
          if client.is_a?(Mantle::Clients::LlamaClient) && orig_max_tokens
            client.as(Mantle::Clients::LlamaClient).max_tokens = orig_max_tokens
          end
          client.temperature = orig_temp if orig_temp
        end
      end
    end

    # Spawns an interactive multi-turn subagent session in a separate fiber.
    # Yields incoming messages to the provided block asynchronously.
    # Enforces both depth limit and a simple token budget (by counting turns/messages).
    def spawn_interactive(
      profile_id : String,
      initial_query : String,
      context : String = "",
      depth : Int32 = 1,
      max_turns : Int32 = 10,
      &on_message : String -> Nil
    ) : Fiber
      if depth > @max_depth
        raise "Subagent depth limit exceeded: #{depth} > #{@max_depth}"
      end

      profile = @profiles[profile_id]?
      unless profile
        raise "Error: Profile '#{profile_id}' not found."
      end

      client = @client
      unless client
        raise "Error: No LLM client configured for subagents"
      end

      full_prompt = build_subagent_prompt(profile, initial_query, context)

      # Run in a separate fiber for concurrency
      spawn do
        begin
          orig_max_tokens = nil
          orig_temp = client.temperature

          if client.is_a?(Mantle::Clients::LlamaClient)
            orig_max_tokens = client.as(Mantle::Clients::LlamaClient).max_tokens
            client.as(Mantle::Clients::LlamaClient).max_tokens = profile.max_tokens
          end
          client.temperature = profile.temperature

          messages = [Mantle::Message.new(role: "user", content: full_prompt)]
          
          turns = 0
          while turns < max_turns
            response = client.execute(messages)
            
            c = response.content || ""
            t = response.thinking || ""
            
            output = if !c.strip.empty?
                       if !t.strip.empty?
                         "🤔 [Thinking Process]\n#{t.strip}\n\n[Response]\n#{c.strip}"
                       else
                         c
                       end
                     else
                       t
                     end
                     
            if !output.strip.empty?
              formatted = format_subagent_response(profile, output)
              on_message.call(formatted)
            end

            # In a real multi-turn we would accept user input back, but for now 
            # we just run the single completion, or we could set up a channel for input.
            # Assuming a basic multi-turn for demonstration, breaking after 1 turn if no tools
            # If there were tools, we would execute them and append to messages.
            break # For now, break after one response if we don't have interactive feedback loop
          end
        rescue ex
          on_message.call("Error in interactive subagent '#{profile.name}': #{ex.message}")
        ensure
          if client
            if client.is_a?(Mantle::Clients::LlamaClient) && orig_max_tokens
              client.as(Mantle::Clients::LlamaClient).max_tokens = orig_max_tokens
            end
            client.temperature = orig_temp if orig_temp
          end
        end
      end
    end

    private def build_subagent_prompt(
      profile : Profile,
      query : String,
      context : String,
    ) : String
      prompt = profile.system_prompt + "\n\n"

      if !context.empty?
        prompt += "Context:\n#{context}\n\n"
      end

      prompt += "Query:\n#{query}\n\n"
      prompt += "Your analysis:"

      prompt
    end

    private def format_subagent_response(profile : Profile, response : String, call_id : String? = nil) : String
      id_str = call_id ? " (ID: #{call_id})" : ""
      <<-RESPONSE
      [Subagent: #{profile.name}#{id_str}]
      #{response.strip}
      [End of #{profile.name} analysis]
      RESPONSE
    end

    def self.load_profiles(profiles_dir : String) : Hash(String, Profile)
      profiles = {} of String => Profile

      if Dir.exists?(profiles_dir)
        Dir.glob(File.join(profiles_dir, "*.json")).each do |path|
          begin
            profile = Profile.load_from_file(path)
            profiles[profile.id] = profile
          rescue ex
            STDERR.puts "Warning: Failed to load subagent profile from #{path}: #{ex.message}"
          end
        end
      end

      profiles
    end
  end
end
