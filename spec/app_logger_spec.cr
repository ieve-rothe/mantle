require "./spec_helper"
require "log/spec"
require "../src/mantle/app_logger"

describe "Mantle::Log" do
  it "is configured with the source 'mantle'" do
    Mantle::Log.source.should eq("mantle")
  end

  it "can log messages via standard Crystal Log setup" do
    # Use Crystal's built-in Log.capture to safely test logging
    Log.capture("mantle", :debug) do |logs|
      Mantle::Log.info { "This is a test message" }
      Mantle::Log.debug { "This is a debug message" }
      Mantle::Log.error { "This is an error message" }

      logs.check(:info, /This is a test message/)
      logs.check(:debug, /This is a debug message/)
      logs.check(:error, /This is an error message/)
    end
  end
end
