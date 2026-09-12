require "json"

module Mantle::Subagents
  # Represents a subagent profile defining behavior and constraints.
  class Profile
    include JSON::Serializable

    # Unique identifier for this profile
    property id : String

    # Human-readable name
    property name : String

    # Description of the subagent's role
    property description : String

    # System prompt that defines the behavior
    property system_prompt : String

    # Maximum tokens for subagent response
    property max_tokens : Int32

    # Temperature for generation (lower = more deterministic)
    property temperature : Float64

    # Optional model override for this subagent
    property model_override : String? = nil

    # Optional API URL override for this subagent
    property api_url_override : String? = nil

    # Optional list of tool names allowed for this subagent
    property allowed_tools : Array(String)? = nil

    # Optional max iterations limit for multi-turn execution
    property max_iterations : Int32? = nil

    def initialize(
      @id : String,
      @name : String,
      @description : String,
      @system_prompt : String,
      @max_tokens : Int32 = 1000,
      @temperature : Float64 = 0.7,
      @model_override : String? = nil,
      @api_url_override : String? = nil,
      @allowed_tools : Array(String)? = nil,
      @max_iterations : Int32? = nil,
    )
    end

    # Load a profile from a JSON file
    def self.load_from_file(path : String) : Profile
      File.open(path) do |file|
        from_json(file)
      end
    end

    # Save the profile to a JSON file securely within base_dir
    def save_to_file(path : String, base_dir : String) : Nil
      expanded_path = File.expand_path(path)
      expanded_base_dir = File.expand_path(base_dir).rstrip(File::SEPARATOR) + File::SEPARATOR
      unless expanded_path.starts_with?(expanded_base_dir)
        raise "Security Error: Path traversal attempt detected (path: #{path})"
      end

      File.write(expanded_path, to_pretty_json)
      File.chmod(expanded_path, 0o600)
    end
  end
end
