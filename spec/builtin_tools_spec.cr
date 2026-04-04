require "./spec_helper"
require "../src/mantle/tools"
require "../src/mantle/builtin_tools"
require "file_utils"

describe "Mantle Built-in Tools" do
  describe "BuiltinTool enum" do
    it "contains ReadFile" do
      Mantle::BuiltinTool::ReadFile.should_not be_nil
    end

    it "contains ListDirectory" do
      Mantle::BuiltinTool::ListDirectory.should_not be_nil
    end
  end

  describe "BuiltinToolRegistry" do
    describe "definition_for" do
      it "returns Tool definition for ReadFile" do
        tool = Mantle::BuiltinToolRegistry.definition_for(Mantle::BuiltinTool::ReadFile)

        tool.should be_a(Mantle::Tool)
        tool.type.should eq("function")
        tool.function.name.should eq("read_file")
        tool.function.description.should_not be_empty
      end

      it "ReadFile has correct parameters" do
        tool = Mantle::BuiltinToolRegistry.definition_for(Mantle::BuiltinTool::ReadFile)

        params = tool.function.parameters
        params.type.should eq("object")
        params.properties.has_key?("file_path").should be_true
        params.properties["file_path"].type.should eq("string")
        params.required.should eq(["file_path"])
      end

      it "returns Tool definition for ListDirectory" do
        tool = Mantle::BuiltinToolRegistry.definition_for(Mantle::BuiltinTool::ListDirectory)

        tool.should be_a(Mantle::Tool)
        tool.type.should eq("function")
        tool.function.name.should eq("list_directory")
        tool.function.description.should_not be_empty
      end

      it "ListDirectory has correct parameters" do
        tool = Mantle::BuiltinToolRegistry.definition_for(Mantle::BuiltinTool::ListDirectory)

        params = tool.function.parameters
        params.type.should eq("object")
        params.properties.has_key?("directory_path").should be_true
        params.properties["directory_path"].type.should eq("string")
        # directory_path is optional, so required should be nil or not include it
        if params.required
          params.required.not_nil!.should_not contain("directory_path")
        end
      end

      it "tool definitions serialize to valid JSON" do
        tool = Mantle::BuiltinToolRegistry.definition_for(Mantle::BuiltinTool::ReadFile)
        json = tool.to_json

        # Should be valid JSON
        parsed = JSON.parse(json)
        parsed["type"].should eq("function")
        parsed["function"]["name"].should eq("read_file")
      end
    end

    describe "all_definitions" do
      it "returns array of all built-in tool definitions" do
        tools = Mantle::BuiltinToolRegistry.all_definitions

        tools.should be_a(Array(Mantle::Tool))
        tools.size.should eq(2)
        tool_names = tools.map { |t| t.function.name }
        tool_names.should contain("read_file")
        tool_names.should contain("list_directory")
      end
    end

    describe "definitions_for" do
      it "returns definitions for multiple built-in tools" do
        tools = Mantle::BuiltinToolRegistry.definitions_for([
          Mantle::BuiltinTool::ReadFile,
          Mantle::BuiltinTool::ListDirectory
        ])

        tools.size.should eq(2)
        tool_names = tools.map { |t| t.function.name }
        tool_names.should contain("read_file")
        tool_names.should contain("list_directory")
      end

      it "returns empty array for empty input" do
        tools = Mantle::BuiltinToolRegistry.definitions_for([] of Mantle::BuiltinTool)
        tools.should be_empty
      end

      it "handles single tool in array" do
        tools = Mantle::BuiltinToolRegistry.definitions_for([Mantle::BuiltinTool::ReadFile])
        tools.size.should eq(1)
        tools[0].function.name.should eq("read_file")
      end
    end
  end

  describe "BuiltinToolConfig" do
    it "can be created with working directory" do
      config = Mantle::BuiltinToolConfig.new(
        working_directory: "/tmp"
      )

      config.working_directory.should eq("/tmp")
      config.allowed_paths.should be_nil
    end

    it "can be created with allowed paths" do
      config = Mantle::BuiltinToolConfig.new(
        working_directory: "/tmp",
        allowed_paths: ["/tmp", "/home/user"]
      )

      config.allowed_paths.should eq(["/tmp", "/home/user"])
    end

    it "defaults allowed_paths to nil (working directory only)" do
      config = Mantle::BuiltinToolConfig.new(working_directory: "/tmp")
      config.allowed_paths.should be_nil
    end
  end

  describe "BuiltinToolExecutor" do
    # Setup test files
    temp_dir = "/tmp/mantle_test_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}"
    outside_dir = "/tmp/mantle_test_outside_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}"

    before_all do
      Dir.mkdir_p(temp_dir)
      Dir.mkdir_p(outside_dir)
      File.write("#{temp_dir}/test_file.txt", "Hello, World!")
      File.write("#{temp_dir}/another_file.txt", "Test content")
      File.write("#{outside_dir}/restricted.txt", "Should not access")
    end

    after_all do
      FileUtils.rm_rf(temp_dir)
      FileUtils.rm_rf(outside_dir)
    end

    describe "read_file" do
      it "reads file in working directory with default config" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("test_file.txt")}
        )

        result.should contain("Hello, World!")
      end

      it "reads file with absolute path in working directory" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("#{temp_dir}/test_file.txt")}
        )

        result.should contain("Hello, World!")
      end

      it "rejects file outside working directory with default config" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("#{outside_dir}/restricted.txt")}
        )

        result.should contain("error")
        result.should contain("not allowed")
      end

      it "allows file in explicitly allowed paths" do
        config = Mantle::BuiltinToolConfig.new(
          working_directory: temp_dir,
          allowed_paths: [temp_dir, outside_dir]
        )
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("#{outside_dir}/restricted.txt")}
        )

        result.should contain("Should not access")
      end

      it "returns error for non-existent file" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("nonexistent.txt")}
        )

        result.should contain("error")
      end
    end

    describe "list_directory" do
      it "lists working directory when no path provided" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "list_directory",
          {} of String => JSON::Any
        )

        result.should contain("test_file.txt")
        result.should contain("another_file.txt")
      end

      it "lists working directory when path is '.'" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(".")}
        )

        result.should contain("test_file.txt")
      end

      it "lists directory with absolute path in working directory" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(temp_dir)}
        )

        result.should contain("test_file.txt")
        result.should contain("another_file.txt")
      end

      it "rejects directory outside working directory" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(outside_dir)}
        )

        result.should contain("error")
        result.should contain("not allowed")
      end

      it "allows directory in explicitly allowed paths" do
        config = Mantle::BuiltinToolConfig.new(
          working_directory: temp_dir,
          allowed_paths: [temp_dir, outside_dir]
        )
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(outside_dir)}
        )

        result.should contain("restricted.txt")
      end

      it "returns error for non-existent directory" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new("nonexistent_dir")}
        )

        result.should contain("error")
      end
    end

    describe "unknown tools" do
      it "returns error for unknown tool" do
        config = Mantle::BuiltinToolConfig.new(working_directory: temp_dir)
        executor = Mantle::BuiltinToolExecutor.new(config)

        result = executor.execute(
          "unknown_tool",
          {} of String => JSON::Any
        )

        result.should contain("error")
        result.should contain("Unknown")
      end
    end
  end
end
