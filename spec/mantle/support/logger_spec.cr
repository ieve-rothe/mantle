require "../../spec_helper"
require "../../../src/mantle/support/logger"

describe Mantle::Support::FileLogger do
  describe "#clear_log_file" do
    it "clears the contents of the log file" do
      temp_file_path = File.tempname("mantle_logger_spec", ".log")

      begin
        logger = Mantle::Support::FileLogger.new(temp_file_path, "user", "bot")
        logger.log("test", "test message")

        File.read(temp_file_path).should_not be_empty

        logger.clear_log_file

        File.read(temp_file_path).should eq("")
      ensure
        File.delete(temp_file_path) if File.exists?(temp_file_path)
      end
    end
  end
end
