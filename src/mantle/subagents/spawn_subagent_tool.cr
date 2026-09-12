require "../tools/tools"
require "json"

module Mantle::Subagents
  # A generic, framework-level tool definition for spawning subagents.
  class SpawnSubagentTool
    # The runner to use for execution
    property runner : Runner

    # A proc that returns the parent's current context (e.g. active frame description)
    property context_provider : Proc(String)

    def initialize(@runner : Runner, &@context_provider : -> String)
    end

    def execute(args : Hash(String, JSON::Any), call_id : String? = nil) : String
      if @runner.current_depth >= @runner.max_depth
        return "Error: Subagent depth limit reached (#{@runner.current_depth} >= #{@runner.max_depth}). Spawning subagents is not allowed at this depth."
      end

      profile = args["profile"]?.try(&.as_s)
      query = args["query"]?.try(&.as_s)

      unless profile && query
        return "Error: Missing required arguments 'profile' and 'query'"
      end

      # Automatically construct context grounding from provider
      parent_context = @context_provider.call

      # Append any optional custom context passed in the tool invocation
      custom_context = args["context"]?.try(&.as_s) || ""
      full_context = if custom_context.empty?
                       parent_context
                     else
                       "#{parent_context}\n#{custom_context}"
                     end

      # Delegate execution to the runner
      @runner.spawn(profile, query, full_context, call_id: call_id)
    end

    def to_mantle_tool : Mantle::Tools::Tool
      available_profiles = @runner.profiles.keys.join(", ")
      profiles_str = available_profiles.empty? ? "none" : available_profiles

      Mantle::Tools::Tool.new(
        function: Mantle::Tools::FunctionDefinition.new(
          name: "spawn_subagent",
          description: "Spawn a background subagent to perform adversarial reasoning or deep research on a topic.",
          parameters: Mantle::Tools::ParametersSchema.new(
            properties: {
              "profile" => Mantle::Tools::PropertyDefinition.new(
                type: "string",
                description: "The persona or goal profile for the subagent. Available profiles: #{profiles_str}."
              ),
              "query" => Mantle::Tools::PropertyDefinition.new(
                type: "string",
                description: "The prompt or problem statement for the subagent to work on."
              ),
              "context" => Mantle::Tools::PropertyDefinition.new(
                type: "string",
                description: "Optional background information or code snippet for context."
              ),
            },
            required: ["profile", "query"]
          )
        )
      )
    end
  end
end
