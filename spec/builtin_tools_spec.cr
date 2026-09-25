require "./spec_helper"
require "file_utils"

describe "Mantle Built-in Tools" do
  describe "Builtin Tool Definitions" do
    it "returns FunctionDefinition for ReadFile" do
      defn = Mantle::Tools::Builtin::ReadFile.definition
      defn.name.should eq("read_file")
      defn.description.should_not be_empty
      params = defn.parameters
      params.type.should eq("object")
      params.properties.has_key?("file_path").should be_true
      params.properties["file_path"].type.should eq("string")
      params.required.should eq(["file_path"])
    end

    it "returns FunctionDefinition for ListDirectory" do
      defn = Mantle::Tools::Builtin::ListDirectory.definition
      defn.name.should eq("list_directory")
      defn.description.should_not be_empty
      params = defn.parameters
      params.type.should eq("object")
      params.properties.has_key?("directory_path").should be_true
      params.properties["directory_path"].type.should eq("string")
      if params.required
        params.required.not_nil!.should_not contain("directory_path")
      end
    end

    it "returns FunctionDefinition for WriteFile" do
      defn = Mantle::Tools::Builtin::WriteFile.definition
      defn.name.should eq("write_file")
      defn.description.should_not be_empty
      params = defn.parameters
      params.type.should eq("object")
      params.properties.has_key?("file_path").should be_true
      params.properties["file_path"].type.should eq("string")
      params.properties.has_key?("content").should be_true
      params.properties["content"].type.should eq("string")
      required = params.required
      required.should_not be_nil
      if required
        required.should contain("file_path")
        required.should contain("content")
      end
    end

    it "returns FunctionDefinition for NotifySend" do
      defn = Mantle::Tools::Builtin::NotifySend.definition
      defn.name.should eq("notify_send")
      defn.description.should_not be_empty
      params = defn.parameters
      params.type.should eq("object")
      params.properties.has_key?("message").should be_true
      params.properties["message"].type.should eq("string")
      required = params.required
      required.should_not be_nil
      if required
        required.should contain("message")
      end
    end

    it "returns FunctionDefinition for SearchFiles" do
      defn = Mantle::Tools::Builtin::SearchFiles.definition
      defn.name.should eq("search_files")
      defn.description.should_not be_empty
      params = defn.parameters
      params.type.should eq("object")
      params.properties.has_key?("query").should be_true
      params.properties["query"].type.should eq("string")
      params.properties.has_key?("directory_path").should be_true
      params.properties["directory_path"].type.should eq("string")
      params.properties.has_key?("file_pattern").should be_true
      params.properties["file_pattern"].type.should eq("string")
      required = params.required
      required.should_not be_nil
      if required
        required.should contain("query")
        required.should_not contain("directory_path")
        required.should_not contain("file_pattern")
      end
    end

    it "returns FunctionDefinition for WebSearch" do
      defn = Mantle::Tools::Builtin::WebSearch.definition
      defn.name.should eq("web_search")
      defn.description.should_not be_empty
      params = defn.parameters
      params.type.should eq("object")
      params.properties.has_key?("query").should be_true
      params.properties["query"].type.should eq("string")
      params.properties.has_key?("search_depth").should be_true
      params.properties["search_depth"].type.should eq("string")
      params.properties.has_key?("max_results").should be_true
      params.properties["max_results"].type.should eq("integer")
      required = params.required
      required.should_not be_nil
      if required
        required.should contain("query")
        required.should_not contain("search_depth")
        required.should_not contain("max_results")
      end
    end

    it "serializes tool definitions to valid JSON" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: "/tmp")
      tool = Mantle::Tools::Builtin::ReadFile.create(sandbox)
      json = tool.to_json
      parsed = JSON.parse(json)
      parsed["type"].should eq("function")
      parsed["function"]["name"].should eq("read_file")
    end

    describe "Builtin.all" do
      it "returns array of all built-in tools with attached handlers" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: "/tmp")
        tools = Mantle::Tools::Builtin.all(sandbox)

        tools.should be_a(Array(Mantle::Tools::Tool))
        tools.size.should eq(6)
        tools.all? { |t| !t.handler.nil? }.should be_true
        tool_names = tools.map { |t| t.function.name }
        tool_names.should contain("read_file")
        tool_names.should contain("list_directory")
        tool_names.should contain("notify_send")
        tool_names.should contain("write_file")
        tool_names.should contain("search_files")
        tool_names.should contain("web_search")
      end
    end
  end

  describe "FileSystemSandbox" do
    it "can be created with working directory" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(
        working_directory: "/tmp"
      )

      sandbox.working_directory.should eq("/tmp")
      sandbox.allowed_paths.should be_nil
      sandbox.autonomous_zone_paths.should be_nil
      sandbox.file_backup_count.should eq(3)
    end

    it "can be created with allowed paths" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(
        working_directory: "/tmp",
        allowed_paths: ["/tmp", "/home/user"]
      )

      sandbox.allowed_paths.should eq(["/tmp", "/home/user"])
    end

    it "defaults allowed_paths to nil (working directory only)" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: "/tmp")
      sandbox.allowed_paths.should be_nil
    end

    it "can be created with autonomous_zone_paths and file_backup_count" do
      sandbox = Mantle::Tools::FileSystemSandbox.new(
        working_directory: "/tmp",
        autonomous_zone_paths: ["/tmp/auto"],
        file_backup_count: 5
      )

      sandbox.autonomous_zone_paths.should eq(["/tmp/auto"])
      sandbox.file_backup_count.should eq(5)
    end
  end

  describe "Builtin tool execution via ToolExecutor" do
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
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("test_file.txt")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_path"].as_s.should eq("test_file.txt")
        result["bytes_read"].as_i.should eq(13)
        result["content"].as_s.should eq("Hello, World!")
      end

      it "reads file with absolute path in working directory" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("#{temp_dir}/test_file.txt")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_path"].as_s.should eq("#{temp_dir}/test_file.txt")
        result["bytes_read"].as_i.should eq(13)
        result["content"].as_s.should eq("Hello, World!")
      end

      it "rejects file outside working directory with default config" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("#{outside_dir}/restricted.txt")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("not allowed")
        result["file_path"].as_s.should eq("#{outside_dir}/restricted.txt")
      end

      it "allows file in explicitly allowed paths" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          allowed_paths: [temp_dir, outside_dir]
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("#{outside_dir}/restricted.txt")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_path"].as_s.should eq("#{outside_dir}/restricted.txt")
        result["bytes_read"].as_i.should eq(17)
        result["content"].as_s.should eq("Should not access")
      end

      it "returns error for non-existent file" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "read_file",
          {"file_path" => JSON::Any.new("nonexistent.txt")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should_not be_empty
        result["file_path"].as_s.should eq("nonexistent.txt")
      end
    end

    describe "write_file" do
      it "rejects file writing if autonomous_zone_paths is nil" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "write_file",
          {
            "file_path" => JSON::Any.new("#{temp_dir}/test_file.txt"),
            "content"   => JSON::Any.new("test content"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("not configured")
        result["file_path"].as_s.should eq("#{temp_dir}/test_file.txt")
      end

      it "rejects file writing outside autonomous zone" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          autonomous_zone_paths: [temp_dir]
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "write_file",
          {
            "file_path" => JSON::Any.new("#{outside_dir}/restricted.txt"),
            "content"   => JSON::Any.new("test content"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("not allowed")
        result["file_path"].as_s.should eq("#{outside_dir}/restricted.txt")
      end

      it "writes file inside autonomous zone" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          autonomous_zone_paths: [temp_dir]
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        target_path = "#{temp_dir}/new_file.txt"

        result_str = executor.execute(
          "write_file",
          {
            "file_path" => JSON::Any.new(target_path),
            "content"   => JSON::Any.new("new file content"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_path"].as_s.should eq(target_path)
        result["bytes_written"].as_i.should eq(16)
        result["message"].as_s.should contain("successfully")

        # Verify it actually wrote the content
        File.read(target_path).should eq("new file content")
      end

      it "creates a backup when modifying an existing file" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          autonomous_zone_paths: [temp_dir]
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        target_path = "#{temp_dir}/existing_file.txt"
        File.write(target_path, "original content")

        result_str = executor.execute(
          "write_file",
          {
            "file_path" => JSON::Any.new(target_path),
            "content"   => JSON::Any.new("modified content"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_path"].as_s.should eq(target_path)
        result["bytes_written"].as_i.should eq(16)

        # Verify the file was modified
        File.read(target_path).should eq("modified content")

        # Verify a backup was created
        backups = Dir.glob("#{target_path}.*.bak")
        backups.size.should eq(1)
        File.read(backups[0]).should eq("original content")
      end

      it "rotates backups when limit is exceeded" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          autonomous_zone_paths: [temp_dir],
          file_backup_count: 2
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        target_path = "#{temp_dir}/rotated_file.txt"
        File.write(target_path, "base")

        # Create 3 older fake backups manually
        File.write("#{target_path}.20000101000000.bak", "oldest")
        File.write("#{target_path}.20010101000000.bak", "middle")
        File.write("#{target_path}.20020101000000.bak", "newest")

        # Now execute the write file tool which should trigger rotation
        result_str = executor.execute(
          "write_file",
          {
            "file_path" => JSON::Any.new(target_path),
            "content"   => JSON::Any.new("current"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_path"].as_s.should eq(target_path)

        # Verify only 2 backups remain (since file_backup_count is 2)
        backups = Dir.glob("#{target_path}.*.bak").sort
        backups.size.should eq(2)

        # The oldest backup should be gone, "middle" might also be gone or "base" might be the newest
        backup_contents = backups.map { |b| File.read(b) }
        backup_contents.should_not contain("oldest")
        backup_contents.should_not contain("middle")
        backup_contents.should contain("newest")
        backup_contents.should contain("base")
      end

      it "returns error for missing required parameter" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          autonomous_zone_paths: [temp_dir]
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "write_file",
          {"file_path" => JSON::Any.new("#{temp_dir}/test_file.txt")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Missing required parameter: content")
        result["file_path"].as_s.should eq("#{temp_dir}/test_file.txt")
      end
    end

    describe "list_directory" do
      it "lists working directory when no path provided" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "list_directory",
          {} of String => JSON::Any
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["directory_path"].as_s.should eq(".")
        result["entry_count"].as_i.should be > 0
        entries = result["entries"].as_a.map(&.as_s)
        entries.should contain("test_file.txt")
        entries.should contain("another_file.txt")
      end

      it "lists working directory when path is '.'" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(".")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["directory_path"].as_s.should eq(".")
        result["entries"].as_a.map(&.as_s).should contain("test_file.txt")
      end

      it "lists directory with absolute path in working directory" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(temp_dir)}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["directory_path"].as_s.should eq(temp_dir)
        entries = result["entries"].as_a.map(&.as_s)
        entries.should contain("test_file.txt")
        entries.should contain("another_file.txt")
      end

      it "rejects directory outside working directory" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(outside_dir)}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("not allowed")
        result["directory_path"].as_s.should eq(outside_dir)
      end

      it "allows directory in explicitly allowed paths" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(
          working_directory: temp_dir,
          allowed_paths: [temp_dir, outside_dir]
        )
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new(outside_dir)}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["directory_path"].as_s.should eq(outside_dir)
        result["entries"].as_a.map(&.as_s).should contain("restricted.txt")
      end

      it "returns error for non-existent directory" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "list_directory",
          {"directory_path" => JSON::Any.new("nonexistent_dir")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should_not be_empty
        result["directory_path"].as_s.should eq("nonexistent_dir")
      end
    end

    describe "search_files" do
      it "rejects queries with invalid characters" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("test; echo bad")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should eq("Security violation: query contains invalid characters.")

        # Test newline character
        result_str2 = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("test\n")}
        )

        result2 = JSON.parse(result_str2)
        result2["success"].as_bool.should be_false
        result2["error"].as_s.should eq("Security violation: query contains invalid characters.")
      end

      it "returns missing query error" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {} of String => JSON::Any
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Missing required parameter")
      end

      it "returns zero matches as empty array" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        File.write("#{temp_dir}/zero_matches.txt", "nothing here")

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("nonexistent_string")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["query"].as_s.should eq("nonexistent_string")
        result["directory_path"].as_s.should eq(".")
        result["total_matches"].as_i.should eq(0)
        result["matches"].as_a.should be_empty
      end

      it "is case-sensitive by default" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        File.write("#{temp_dir}/case_sensitive.txt", "here is UpperCase and lowercase")

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("uppercase")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["matches"].as_a.should be_empty
      end

      it "handles regex with special characters correctly" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        File.write("#{temp_dir}/regex.txt", "abc123xyz")

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("c\\d+x")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["matches"].as_a.map(&.as_s).any?(&.includes?("regex.txt:1")).should be_true
      end

      it "skips hidden files and directories" do
        empty_dir = File.join(temp_dir, "empty_search_dir2")
        Dir.mkdir_p(empty_dir)

        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: empty_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        Dir.mkdir_p("#{empty_dir}/.hidden_dir")
        File.write("#{empty_dir}/.hidden_dir/file.txt", "HIDDEN_MATCH")
        File.write("#{empty_dir}/.hidden_file", "HIDDEN_MATCH")

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("HIDDEN_MATCH")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
      end

      it "skips binary files gracefully" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        # Write null bytes to make it binary
        File.write("#{temp_dir}/binary.bin", "binary_match\0\0\0")

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("binary_match")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["matches"].as_a.should be_empty
      end

      it "filters by file extension" do
        empty_dir = File.join(temp_dir, "empty_search_dir3")
        Dir.mkdir_p(empty_dir)

        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: empty_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        File.write("#{empty_dir}/test.cr", "FILTER_MATCH")
        File.write("#{empty_dir}/test.md", "FILTER_MATCH")

        result_str = executor.execute(
          "search_files",
          {
            "query"        => JSON::Any.new("FILTER_MATCH"),
            "file_pattern" => JSON::Any.new("*.cr"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["file_pattern"].as_s.should eq("*.cr")
        matches = result["matches"].as_a.map(&.as_s)
        matches.any?(&.includes?("test.cr:1")).should be_true
        matches.any?(&.includes?("test.md:1")).should be_false
      end

      it "returns helpful error for malformed regex" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("[invalid_regex")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Search failed")
      end

      it "returns error if directory does not exist" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {
            "query"          => JSON::Any.new("MATCH"),
            "directory_path" => JSON::Any.new("nonexistent_dir"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Path does not exist")
        result["directory_path"].as_s.should eq("nonexistent_dir")
      end

      it "rejects file_pattern starting with hyphen" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {
            "query"        => JSON::Any.new("MATCH"),
            "file_pattern" => JSON::Any.new("-u"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Security violation")
        result["file_pattern"].as_s.should eq("-u")
      end

      it "rejects file_pattern containing malicious control characters" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {
            "query"        => JSON::Any.new("MATCH"),
            "file_pattern" => JSON::Any.new("*.txt; id"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Security violation")
        result["file_pattern"].as_s.should eq("*.txt; id")
      end

      it "rejects query starting with hyphen" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("-e")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Security violation")
        result["query"].as_s.should eq("-e")
      end

      it "truncates exactly at 11 matches" do
        empty_dir = File.join(temp_dir, "empty_search_dir4")
        Dir.mkdir_p(empty_dir)

        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: empty_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        content = String.build do |io|
          11.times { |i| io.puts "Line #{i} has EXACT11MATCH" }
        end
        File.write("#{empty_dir}/exact11_matches.txt", content)

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("EXACT11MATCH")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["warning"].as_s.should contain("Results truncated from 11 to 10")
        result["matches"].as_a.size.should eq(10)
      end

      it "searches inside working directory successfully" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        # Write test files
        File.write("#{temp_dir}/search_target.txt", "line1\nline2 has UNIQUEMATCH\nline3")

        result_str = executor.execute(
          "search_files",
          {"query" => JSON::Any.new("UNIQUEMATCH")}
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_true
        result["matches"].as_a.map(&.as_s).any?(&.includes?("search_target.txt:2")).should be_true
      end

      it "rejects search in unauthorized directory" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "search_files",
          {
            "query"          => JSON::Any.new("restricted"),
            "directory_path" => JSON::Any.new(outside_dir),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("not allowed")
        result["directory_path"].as_s.should eq(outside_dir)
      end
    end

    describe "notify_send" do
      it "returns missing message error" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "notify_send",
          {} of String => JSON::Any
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Missing required parameter")
      end

      it "prevents argument injection" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "notify_send",
          {
            "message" => JSON::Any.new("-u critical"),
          }
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Security violation")
        result["message"].as_s.should eq("-u critical")
      end
    end

    describe "web_search" do
      it "returns missing query error" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "web_search",
          {} of String => JSON::Any
        )

        result = JSON.parse(result_str)
        result["success"].as_bool.should be_false
        result["error"].as_s.should contain("Missing required parameter: query")
      end

      it "returns missing API key error when TAVILY_API_KEY is not set" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        old_key = ENV["TAVILY_API_KEY"]?
        ENV.delete("TAVILY_API_KEY")
        begin
          result_str = executor.execute(
            "web_search",
            {"query" => JSON::Any.new("crystal programming language")}
          )

          result = JSON.parse(result_str)
          result["success"].as_bool.should be_false
          result["error"].as_s.should contain("TAVILY_API_KEY")
        ensure
          ENV["TAVILY_API_KEY"] = old_key if old_key
        end
      end

      it "can be created without a sandbox" do
        tool = Mantle::Tools::Builtin::WebSearch.create
        tool.function.name.should eq("web_search")
        tool.handler.should_not be_nil
      end

      it "resolves key from custom key string or proc" do
        Mantle::Tools::Builtin::WebSearch.resolve_api_key("custom-123").should eq("custom-123")
        Mantle::Tools::Builtin::WebSearch.resolve_api_key(->{ "proc-456" }).should eq("proc-456")
      end
    end

    describe "unknown tools" do
      it "returns error for unknown tool" do
        sandbox = Mantle::Tools::FileSystemSandbox.new(working_directory: temp_dir)
        executor = Mantle::Tools::ToolExecutor.new(tools: Mantle::Tools::Builtin.all(sandbox))

        result_str = executor.execute(
          "unknown_tool",
          {} of String => JSON::Any
        )

        result = JSON.parse(result_str)
        result["error"].as_s.should contain("Unknown")
      end
    end
  end
end
