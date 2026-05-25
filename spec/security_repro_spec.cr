require "./spec_helper"
require "file_utils"

describe "Mantle Built-in Tools Security" do
  temp_dir = "/tmp/mantle_security_test_#{Time.utc.to_unix_ms}"
  allowed_dir = "#{temp_dir}/allowed"
  secret_dir = "#{temp_dir}/allowed_secret"

  before_all do
    Dir.mkdir_p(allowed_dir)
    Dir.mkdir_p(secret_dir)
    File.write("#{allowed_dir}/public.txt", "public content")
    File.write("#{secret_dir}/private.txt", "private content")
  end

  after_all do
    FileUtils.rm_rf(temp_dir)
  end

  it "does not allow access to a directory starting with the same prefix but not a subpath" do
    config = Mantle::Tools::BuiltinToolConfig.new(working_directory: allowed_dir)
    executor = Mantle::Tools::BuiltinToolExecutor.new(config)

    # This should fail because secret_dir is NOT in allowed_dir,
    # even though secret_dir's path starts with allowed_dir's path.
    result = executor.execute(
      "read_file",
      {"file_path" => JSON::Any.new("#{secret_dir}/private.txt")}
    )

    result.should contain("error")
    result.should contain("not allowed")
  end
end
