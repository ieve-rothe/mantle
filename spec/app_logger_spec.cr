require "./spec_helper"
require "../src/mantle/app_logger"

describe Mantle::AppLogger do
  it "is enabled when DEBUG_MANTLE is set" do
    ENV["DEBUG_MANTLE"] = "1"
    logger = Mantle::AppLogger.new
    logger.enabled.should be_true
    ENV.delete("DEBUG_MANTLE")
  end

  it "is disabled when DEBUG_MANTLE is not set" do
    ENV.delete("DEBUG_MANTLE")
    logger = Mantle::AppLogger.new
    logger.enabled.should be_false
  end

  it "outputs info messages when enabled" do
    io = IO::Memory.new
    logger = Mantle::AppLogger.new(io)
    logger.enabled = true
    logger.info("test message")
    io.to_s.should eq("[Mantle INFO] test message\n")
  end

  it "does not output info messages when disabled" do
    io = IO::Memory.new
    logger = Mantle::AppLogger.new(io)
    logger.enabled = false
    logger.info("test message")
    io.to_s.should be_empty
  end

  it "outputs debug messages when enabled" do
    io = IO::Memory.new
    logger = Mantle::AppLogger.new(io)
    logger.enabled = true
    logger.debug("debug message")
    io.to_s.should eq("[Mantle DEBUG] debug message\n")
  end

  it "outputs error messages when enabled" do
    io = IO::Memory.new
    logger = Mantle::AppLogger.new(io)
    logger.enabled = true
    logger.error("error message")
    io.to_s.should eq("[Mantle ERROR] error message\n")
  end

  it "outputs info messages with block when enabled" do
    io = IO::Memory.new
    logger = Mantle::AppLogger.new(io)
    logger.enabled = true
    logger.info { "test message from block" }
    io.to_s.should eq("[Mantle INFO] test message from block\n")
  end

  it "outputs warn messages when enabled" do
    io = IO::Memory.new
    logger = Mantle::AppLogger.new(io)
    logger.enabled = true
    logger.warn("warn message")
    io.to_s.should eq("[Mantle WARN] warn message\n")
  end
end
