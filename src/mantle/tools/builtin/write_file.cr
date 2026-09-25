# mantle/tools/builtin/write_file.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../tools"
require "../file_system_sandbox"

module Mantle::Tools::Builtin
  module WriteFile
    def self.definition : FunctionDefinition
      FunctionDefinition.new(
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
    end

    def self.create(sandbox : FileSystemSandbox) : Tool
      Tool.new(definition) do |arguments|
        execute(sandbox, arguments)
      end
    end

    def self.execute(sandbox : FileSystemSandbox, arguments : Hash(String, JSON::Any)) : String
      file_path = arguments["file_path"]?.try(&.as_s?)
      content = arguments["content"]?.try(&.as_s?)

      unless file_path
        return {success: false, error: "Missing required parameter: file_path"}.to_json
      end

      unless content
        return {success: false, error: "Missing required parameter: content", file_path: file_path}.to_json
      end

      unless sandbox.autonomous_zone_paths
        return {success: false, error: "Writing files is not configured (no autonomous zone specified)", file_path: file_path}.to_json
      end

      absolute_path = sandbox.resolve_path(file_path)

      unless sandbox.path_in_autonomous_zone?(absolute_path)
        return {success: false, error: "Access to path not allowed (outside autonomous zone): #{absolute_path}", file_path: file_path}.to_json
      end

      begin
        Dir.mkdir_p(File.dirname(absolute_path))

        if File.exists?(absolute_path)
          sandbox.create_file_backup(absolute_path)
        end

        File.write(absolute_path, content)
        {success: true, message: "File written successfully.", file_path: file_path, bytes_written: content.bytesize}.to_json
      rescue ex
        {success: false, error: "Error writing file: #{ex.message}", file_path: file_path}.to_json
      end
    end
  end
end
