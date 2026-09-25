# mantle/tools/builtin/list_directory.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../tools"
require "../file_system_sandbox"

module Mantle::Tools::Builtin
  module ListDirectory
    def self.definition : FunctionDefinition
      FunctionDefinition.new(
        name: "list_directory",
        description: "List the contents (files and subdirectories) of a directory",
        parameters: ParametersSchema.new(
          properties: {
            "directory_path" => PropertyDefinition.new(
              type: "string",
              description: "Path to the directory to list. Defaults to current directory if not specified."
            ),
          },
          required: nil
        )
      )
    end

    def self.create(sandbox : FileSystemSandbox) : Tool
      Tool.new(definition) do |arguments|
        execute(sandbox, arguments)
      end
    end

    def self.execute(sandbox : FileSystemSandbox, arguments : Hash(String, JSON::Any)) : String
      dir_path = arguments["directory_path"]?.try(&.as_s) || "."
      absolute_path = sandbox.resolve_path(dir_path)

      unless sandbox.path_allowed?(absolute_path)
        return {success: false, error: "Access to path not allowed: #{absolute_path}", directory_path: dir_path}.to_json
      end

      begin
        entries = Dir.children(absolute_path)
        {
          success:        true,
          directory_path: dir_path,
          entry_count:    entries.size,
          entries:        entries,
        }.to_json
      rescue ex
        {success: false, error: "Error listing directory: #{ex.message}", directory_path: dir_path}.to_json
      end
    end
  end
end
