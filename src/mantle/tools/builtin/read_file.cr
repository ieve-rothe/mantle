# mantle/tools/builtin/read_file.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../tools"
require "../file_system_sandbox"

module Mantle::Tools::Builtin
  module ReadFile
    def self.definition : FunctionDefinition
      FunctionDefinition.new(
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
    end

    def self.create(sandbox : FileSystemSandbox) : Tool
      Tool.new(definition) do |arguments|
        execute(sandbox, arguments)
      end
    end

    def self.execute(sandbox : FileSystemSandbox, arguments : Hash(String, JSON::Any)) : String
      file_path = arguments["file_path"]?.try(&.as_s)

      unless file_path
        return {success: false, error: "Missing required parameter: file_path"}.to_json
      end

      absolute_path = sandbox.resolve_path(file_path)

      unless sandbox.path_allowed?(absolute_path)
        return {success: false, error: "Access to path not allowed: #{absolute_path}", file_path: file_path}.to_json
      end

      begin
        content = File.read(absolute_path)
        {
          success:    true,
          file_path:  file_path,
          bytes_read: content.bytesize,
          content:    content,
        }.to_json
      rescue ex
        {success: false, error: "Error reading file: #{ex.message}", file_path: file_path}.to_json
      end
    end
  end
end
