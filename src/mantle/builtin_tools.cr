require "./tools"
require "json"

module Mantle
  # Enum representing available built-in tools
  # Applications opt into these by passing the enum values
  enum BuiltinTool
    ReadFile
    ListDirectory
    NotifySend
    WriteFile
    SearchFiles
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
      when BuiltinTool::WriteFile
        write_file_definition
      when BuiltinTool::SearchFiles
        search_files_definition
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
              ),
            },
            required: ["file_path"]
          )
        )
      )
    end

    private def self.search_files_definition : Tool
      Tool.new(
        function: FunctionDefinition.new(
          name: "search_files",
          description: "Search for a string in files using ripgrep or grep. Returns a heavily truncated list of matches.",
          parameters: ParametersSchema.new(
            properties: {
              "query" => PropertyDefinition.new(
                type: "string",
                description: "The search string or regex to find."
              ),
              "directory_path" => PropertyDefinition.new(
                type: "string",
                description: "Path to the directory to search. Defaults to current directory if not specified."
              ),
              "file_pattern" => PropertyDefinition.new(
                type: "string",
                description: "Optional glob pattern to filter files (e.g., '*.cr', '*.md')."
              ),
            },
            required: ["query"]
          )
        )
      )
    end

    private def self.write_file_definition : Tool
      Tool.new(
        function: FunctionDefinition.new(
          name: "write_file",
          description: "Write content to a file at the specified path",
          parameters: ParametersSchema.new(
            properties: {
              "file_path" => PropertyDefinition.new(
                type: "string",
                description: "Path to the file to write"
              ),
              "content" => PropertyDefinition.new(
                type: "string",
                description: "Content to write to the file"
              ),
            },
            required: ["file_path", "content"]
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
              ),
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
              ),
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
    property autonomous_zone_paths : Array(String)?
    property file_backup_count : Int32

    def initialize(
      @working_directory : String,
      @allowed_paths : Array(String)? = nil,
      @notify_icon : String? = nil,
      @autonomous_zone_paths : Array(String)? = nil,
      @file_backup_count : Int32 = 3,
    )
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
      when "write_file"
        execute_write_file(arguments)
      when "search_files"
        execute_search_files(arguments)
      else
        {error: "Unknown built-in tool: #{tool_name}"}.to_json
      end
    end

    private def execute_write_file(arguments : Hash(String, JSON::Any)) : String
      file_path = arguments["file_path"]?.try(&.as_s?)
      content = arguments["content"]?.try(&.as_s?)

      unless file_path
        return {error: "Missing required parameter: file_path"}.to_json
      end

      unless content
        return {error: "Missing required parameter: content"}.to_json
      end

      unless @config.autonomous_zone_paths
        return {error: "Writing files is not configured (no autonomous zone specified)"}.to_json
      end

      absolute_path = resolve_path(file_path)

      unless path_in_autonomous_zone?(absolute_path)
        return {error: "Access to path not allowed (outside autonomous zone): #{absolute_path}"}.to_json
      end

      begin
        # Ensure the parent directory exists
        Dir.mkdir_p(File.dirname(absolute_path))

        # Create a backup if the file already exists
        if File.exists?(absolute_path)
          create_file_backup(absolute_path)
        end

        # Write the file
        File.write(absolute_path, content)
        {success: true, message: "File written successfully."}.to_json
      rescue ex
        {error: "Error writing file: #{ex.message}"}.to_json
      end
    end

    private def create_file_backup(absolute_path : String)
      # Create new backup
      timestamp = Time.utc.to_s("%Y%m%d%H%M%S")
      backup_path = "#{absolute_path}.#{timestamp}.bak"
      File.copy(absolute_path, backup_path)

      # Rotate old backups
      backup_limit = @config.file_backup_count

      # Find all backups for this file
      dir = File.dirname(absolute_path)
      filename = File.basename(absolute_path)

      # Use Dir.children instead of Dir.glob to safely handle special characters in paths
      if Dir.exists?(dir)
        backups = Dir.children(dir)
          .select { |f| f.starts_with?("#{filename}.") && f.ends_with?(".bak") }
          .map { |f| File.join(dir, f) }
          .sort

        # If we have more backups than the limit, delete the oldest ones
        if backups.size > backup_limit
          backups_to_delete = backups.size - backup_limit
          backups[0, backups_to_delete].each do |old_backup|
            File.delete(old_backup) if File.exists?(old_backup)
          end
        end
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

    private def execute_search_files(arguments : Hash(String, JSON::Any)) : String
      query = arguments["query"]?.try(&.as_s)

      unless query
        return {error: "Missing required parameter: query"}.to_json
      end

      # Default to "." (working directory) if no path provided
      dir_path = arguments["directory_path"]?.try(&.as_s) || "."
      file_pattern = arguments["file_pattern"]?.try(&.as_s)

      if file_pattern
        # Validate file_pattern to prevent argument injection and malicious payloads
        if file_pattern.starts_with?("-")
          return {error: "Security violation: file_pattern cannot start with a hyphen."}.to_json
        end

        if file_pattern =~ /[;\n\r&|`$]/
          return {error: "Security violation: file_pattern contains invalid characters."}.to_json
        end
      end

      # Resolve to absolute path
      absolute_path = resolve_path(dir_path)

      # Check if path is allowed
      unless path_allowed?(absolute_path)
        return {error: "Access to path not allowed: #{absolute_path}"}.to_json
      end

      begin
        # If absolute_path exists but is a file, we want to skip directory logic and just search the file
        unless File.exists?(absolute_path)
          return {error: "Path does not exist: #{absolute_path}"}.to_json
        end

        # Determine whether to use rg or grep
        use_rg = !Process.find_executable("rg").nil?

        output = String::Builder.new
        error = String::Builder.new

        if use_rg
          args = ["-n", "-H", "--no-heading"]
          if file_pattern
            args << "-g"
            args << file_pattern
          end
          args << "--"
          args << query
          args << absolute_path
          status = Process.run("rg", args, output: output, error: error)
        else
          # grep: -r recursive, -n line numbers, -I ignore binary files, -H with filename
          args = ["-rnIH"]
          if file_pattern
            args << "--include=#{file_pattern}"
          end
          args << "--"
          args << query
          args << absolute_path
          status = Process.run("grep", args, output: output, error: error)
        end

        output_str = output.to_s

        # Handle process failures (like bad regex)
        if !status.success? && status.exit_code > 1
          err_msg = error.to_s.strip
          err_msg = "Command failed with exit code #{status.exit_code}" if err_msg.empty?
          return {error: "Search failed: #{err_msg}"}.to_json
        end

        unless status.success? && !output_str.empty?
          # grep/rg return 1 if no lines are found
          return {success: true, matches: [] of String}.to_json
        end

        # Parse and truncate matches
        matches = output_str.lines.map do |line|
          parts = line.split(":", 3) # Split into file, line, and rest (content)
          if parts.size >= 2
            "#{parts[0]}:#{parts[1]}"
          else
            line
          end
        end

        truncated_matches = matches.first(10)

        result = {success: true, matches: truncated_matches}

        if matches.size > 10
          result = result.merge({warning: "Results truncated from #{matches.size} to 10."})
        end

        result.to_json
      rescue ex
        {error: "Error executing search: #{ex.message}"}.to_json
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

    # Check if a path is within the autonomous zone
    private def path_in_autonomous_zone?(absolute_path : String) : Bool
      if zone_paths = @config.autonomous_zone_paths
        zone_paths.any? do |zone_path|
          is_subpath?(absolute_path, zone_path)
        end
      else
        false
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
