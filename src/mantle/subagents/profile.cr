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

    def initialize(
      @id : String,
      @name : String,
      @description : String,
      @system_prompt : String,
      @max_tokens : Int32 = 1000,
      @temperature : Float64 = 0.7,
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
