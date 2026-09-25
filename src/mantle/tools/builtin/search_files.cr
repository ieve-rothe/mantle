# mantle/tools/builtin/search_files.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../tools"
require "../file_system_sandbox"

module Mantle::Tools::Builtin
  module SearchFiles
    def self.definition : FunctionDefinition
      FunctionDefinition.new(
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
    end

    def self.create(sandbox : FileSystemSandbox) : Tool
      Tool.new(definition) do |arguments|
        execute(sandbox, arguments)
      end
    end

    def self.execute(sandbox : FileSystemSandbox, arguments : Hash(String, JSON::Any)) : String
      query = arguments["query"]?.try(&.as_s)

      unless query
        return {success: false, error: "Missing required parameter: query"}.to_json
      end

      # Validate query to prevent argument injection
      if query.strip.starts_with?("-")
        return {
          success: false,
          error:   "Security violation: query cannot start with a hyphen.",
          query:   query,
        }.to_json
      end

      if query =~ /[;\n\r&|`$]/
        return {
          success: false,
          error:   "Security violation: query contains invalid characters.",
          query:   query,
        }.to_json
      end

      dir_path = arguments["directory_path"]?.try(&.as_s) || "."
      file_pattern = arguments["file_pattern"]?.try(&.as_s)

      if file_pattern
        if file_pattern.strip.starts_with?("-")
          return {
            success:        false,
            error:          "Security violation: file_pattern cannot start with a hyphen.",
            query:          query,
            directory_path: dir_path,
            file_pattern:   file_pattern,
          }.to_json
        end

        if file_pattern =~ /[;\n\r&|`$]/
          return {
            success:        false,
            error:          "Security violation: file_pattern contains invalid characters.",
            query:          query,
            directory_path: dir_path,
            file_pattern:   file_pattern,
          }.to_json
        end
      end

      absolute_path = sandbox.resolve_path(dir_path)

      unless sandbox.path_allowed?(absolute_path)
        return {
          success:        false,
          error:          "Access to path not allowed: #{absolute_path}",
          query:          query,
          directory_path: dir_path,
          file_pattern:   file_pattern,
        }.to_json
      end

      begin
        unless File.exists?(absolute_path)
          return {
            success:        false,
            error:          "Path does not exist: #{absolute_path}",
            query:          query,
            directory_path: dir_path,
            file_pattern:   file_pattern,
          }.to_json
        end

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

        if !status.success? && status.exit_code > 1
          err_msg = error.to_s.strip
          err_msg = "Command failed with exit code #{status.exit_code}" if err_msg.empty?
          return {
            success:        false,
            error:          "Search failed: #{err_msg}",
            query:          query,
            directory_path: dir_path,
            file_pattern:   file_pattern,
          }.to_json
        end

        unless status.success? && !output_str.empty?
          return {
            success:        true,
            query:          query,
            directory_path: dir_path,
            file_pattern:   file_pattern,
            total_matches:  0,
            matches:        [] of String,
          }.to_json
        end

        matches = output_str.lines.map do |line|
          parts = line.split(":", 3)
          if parts.size >= 2
            "#{parts[0]}:#{parts[1]}"
          else
            line
          end
        end

        truncated_matches = matches.first(10)

        JSON.build do |json|
          json.object do
            json.field "success", true
            json.field "query", query
            json.field "directory_path", dir_path
            json.field "file_pattern", file_pattern
            json.field "total_matches", matches.size
            json.field "matches", truncated_matches
            if matches.size > 10
              json.field "warning", "Results truncated from #{matches.size} to 10."
            end
          end
        end
      rescue ex
        {
          success:        false,
          error:          "Error executing search: #{ex.message}",
          query:          query,
          directory_path: dir_path,
          file_pattern:   file_pattern,
        }.to_json
      end
    end
  end
end
