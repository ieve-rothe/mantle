require "./tools"
require "json"

module Mantle
  # Enum representing available built-in tools
  # Applications opt into these by passing the enum values
  enum BuiltinTool
    ReadFile
    ListDirectory
  end

  # Registry that provides tool definitions for built-in tools
  # Maps enum values to their corresponding Tool definitions
  class BuiltinToolRegistry
    # Get the Tool definition for a specific built-in tool
    def self.definition_for(builtin : BuiltinTool) : Tool
      case builtin
      when BuiltinTool::ReadFile
        read_file_definition
      when BuiltinTool::ListDirectory
        list_directory_definition
      else
        raise "Unknown builtin tool: #{builtin}"
      end
    end

    # Get Tool definitions for multiple built-in tools
    def self.definitions_for(builtins : Array(BuiltinTool)) : Array(Tool)
      builtins.map { |b| definition_for(b) }
    end

    # Get all available built-in tool definitions
    def self.all_definitions : Array(Tool)
      BuiltinTool.values.map { |b| definition_for(b) }
    end

    # Private helper methods to build individual tool definitions

    private def self.read_file_definition : Tool
      Tool.new(
        function: FunctionDefinition.new(
          name: "read_file",
          description: "Read and return the contents of a file at the specified path",
          parameters: ParametersSchema.new(
            properties: {
              "file_path" => PropertyDefinition.new(
                type: "string",
                description: "Path to the file to read"
              )
            },
            required: ["file_path"]
          )
        )
      )
    end

    private def self.list_directory_definition : Tool
      Tool.new(
        function: FunctionDefinition.new(
          name: "list_directory",
          description: "List the contents (files and subdirectories) of a directory",
          parameters: ParametersSchema.new(
            properties: {
              "directory_path" => PropertyDefinition.new(
                type: "string",
                description: "Path to the directory to list. Defaults to current directory if not specified."
              )
            },
            required: nil # directory_path is optional
          )
        )
      )
    end
  end

  # Configuration for built-in tool execution safety
  # Controls which paths built-in tools can access
  class BuiltinToolConfig
    property working_directory : String
    property allowed_paths : Array(String)?

    def initialize(@working_directory : String, @allowed_paths : Array(String)? = nil)
    end
  end

  # Executes built-in tools with safety restrictions
  # Validates all file system access against allowed paths
  class BuiltinToolExecutor
    @config : BuiltinToolConfig

    def initialize(@config : BuiltinToolConfig)
    end

    # Execute a built-in tool by name with given arguments
    # Returns JSON-formatted result string or error message
    def execute(tool_name : String, arguments : Hash(String, JSON::Any)) : String
      case tool_name
      when "read_file"
        execute_read_file(arguments)
      when "list_directory"
        execute_list_directory(arguments)
      else
        {error: "Unknown built-in tool: #{tool_name}"}.to_json
      end
    end

    private def execute_read_file(arguments : Hash(String, JSON::Any)) : String
      file_path = arguments["file_path"]?.try(&.as_s)

      unless file_path
        return {error: "Missing required parameter: file_path"}.to_json
      end

      # Resolve to absolute path
      absolute_path = resolve_path(file_path)

      # Check if path is allowed
      unless path_allowed?(absolute_path)
        return {error: "Access to path not allowed: #{absolute_path}"}.to_json
      end

      # Read the file
      begin
        content = File.read(absolute_path)
        {success: true, content: content}.to_json
      rescue ex
        {error: "Error reading file: #{ex.message}"}.to_json
      end
    end

    private def execute_list_directory(arguments : Hash(String, JSON::Any)) : String
      # Default to "." (working directory) if no path provided
      dir_path = arguments["directory_path"]?.try(&.as_s) || "."

      # Resolve to absolute path
      absolute_path = resolve_path(dir_path)

      # Check if path is allowed
      unless path_allowed?(absolute_path)
        return {error: "Access to path not allowed: #{absolute_path}"}.to_json
      end

      # List directory contents
      begin
        entries = Dir.children(absolute_path)
        {success: true, entries: entries}.to_json
      rescue ex
        {error: "Error listing directory: #{ex.message}"}.to_json
      end
    end

    # Resolve a path to absolute form, handling relative paths
    private def resolve_path(path : String) : String
      if path.starts_with?("/")
        # Already absolute
        File.expand_path(path)
      else
        # Relative to working directory
        File.expand_path(path, @config.working_directory)
      end
    end

    # Check if a path is within the allowed paths
    private def path_allowed?(absolute_path : String) : Bool
      if allowed = @config.allowed_paths
        # Check if path is within any of the explicitly allowed paths
        allowed.any? do |allowed_path|
          expanded_allowed = File.expand_path(allowed_path)
          absolute_path.starts_with?(expanded_allowed)
        end
      else
        # Default: only allow paths within working directory
        expanded_working = File.expand_path(@config.working_directory)
        absolute_path.starts_with?(expanded_working)
      end
    end
  end
end
