require "socket"
require "time"

MOCK_PORT = 11435

WORKSPACE_ROOT = [
  File.expand_path("../../../", __DIR__),
  File.expand_path("../../../../", __DIR__),
].find { |path| File.exists?(File.join(path, "llm_mock")) } || File.expand_path("../../../", __DIR__)

FIXTURE_PATH = File.join(WORKSPACE_ROOT, "empaws/.empaws_local/llm_calls.jsonl")
MOCK_BIN     = File.join(WORKSPACE_ROOT, "llm_mock/bin/llm_mock")

module LlmMockHelper
  @@process : Process? = nil

  def self.start
    return if @@process

    unless File.exists?(MOCK_BIN)
      raise "llm_mock binary not found at #{MOCK_BIN}. Build it before running integration specs."
    end

    @@process = Process.new(
      MOCK_BIN,
      args: ["-p", MOCK_PORT.to_s, "-f", FIXTURE_PATH],
      output: Process::Redirect::Close,
      error: Process::Redirect::Close
    )

    wait_for_port(MOCK_PORT)
  end

  def self.stop
    @@process.try do |p|
      p.terminate rescue nil
      p.wait rescue nil
    end
    @@process = nil
  end

  private def self.wait_for_port(port : Int32, timeout : Time::Span = 5.seconds)
    deadline = Time.instant + timeout
    loop do
      begin
        socket = TCPSocket.new("127.0.0.1", port)
        socket.close
        break
      rescue Socket::ConnectError
        if Time.instant > deadline
          stop
          raise "llm_mock failed to bind on port #{port} within #{timeout}"
        end
        sleep 50.milliseconds
      end
    end
  end
end

at_exit do
  LlmMockHelper.stop
end
