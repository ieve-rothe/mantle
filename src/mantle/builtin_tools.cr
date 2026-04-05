require "./tools"
require "json"

module Mantle
  # Enum representing available built-in tools
  # Applications opt into these by passing the enum values
  enum BuiltinTool
    ReadFile
    ListDirectory
    NotifySend
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
      when BuiltinTool::NotifySend
        notify_send_definition
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

    private def self.notify_send_definition : Tool
      Tool.new(
        function: FunctionDefinition.new(
          name: "notify_send",
          description: "Send a desktop notification to the user",
          parameters: ParametersSchema.new(
            properties: {
              "message" => PropertyDefinition.new(
                type: "string",
                description: "The message content of the notification"
              )
            },
            required: ["message"]
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
    property notify_icon : String?

    def initialize(@working_directory : String, @allowed_paths : Array(String)? = nil, @notify_icon : String? = nil)
    end
  end

  # Executes built-in tools with safety restrictions
  # Validates all file system access against allowed paths
  class BuiltinToolExecutor
    @config : BuiltinToolConfig
    @bot_name : String

    def initialize(@config : BuiltinToolConfig, @bot_name : String = "Assistant")
    end

    # Execute a built-in tool by name with given arguments
    # Returns JSON-formatted result string or error message
    def execute(tool_name : String, arguments : Hash(String, JSON::Any)) : String
      case tool_name
      when "read_file"
        execute_read_file(arguments)
      when "list_directory"
        execute_list_directory(arguments)
      when "notify_send"
        execute_notify_send(arguments)
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

    private def execute_notify_send(arguments : Hash(String, JSON::Any)) : String
      message = arguments["message"]?.try(&.as_s?)

      unless message
        return {error: "Missing required parameter: message"}.to_json
      end

      # Build notify-send arguments
      args = [@bot_name, message]

      if icon = @config.notify_icon
        args << "--icon=#{icon}"
      end

      begin
        status = Process.run("notify-send", args)
        if status.success?
          {success: true, message: "Notification sent successfully"}.to_json
        else
          {error: "Error sending notification. Exit code: #{status.exit_code}"}.to_json
        end
      rescue ex
        {error: "Error executing notify-send: #{ex.message}"}.to_json
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
          is_subpath?(absolute_path, allowed_path)
        end
      else
        # Default: only allow paths within working directory
        is_subpath?(absolute_path, @config.working_directory)
      end
    end

    # Helper to check if a path is a subpath of a base directory
    private def is_subpath?(path : String, base : String) : Bool
      expanded_path = File.expand_path(path)
      expanded_base = File.expand_path(base)

      # Equal path is allowed
      return true if expanded_path == expanded_base

      # Must start with base + separator to ensure it's a true subpath
      # and not just a path that shares a prefix (e.g., /tmp/allowed_secret vs /tmp/allowed)
      base_with_separator = expanded_base.ends_with?(File::SEPARATOR) ? expanded_base : expanded_base + File::SEPARATOR
      expanded_path.starts_with?(base_with_separator)
    end
  end
end
