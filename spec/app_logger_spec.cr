require "./spec_helper"
require "log/spec"

describe "Mantle::Support::Log" do
  it "is configured with the source 'mantle'" do
    Mantle::Support::Log.source.should eq("mantle")
  end

  it "can log messages via standard Crystal Log setup" do
    # Use Crystal's built-in Log.capture to safely test logging
    Log.capture("mantle", :debug) do |logs|
      Mantle::Support::Log.info { "This is a test message" }
      Mantle::Support::Log.debug { "This is a debug message" }
      Mantle::Support::Log.error { "This is an error message" }

      logs.check(:info, /This is a test message/)
      logs.check(:debug, /This is a debug message/)
      logs.check(:error, /This is an error message/)
    end
  end
end
