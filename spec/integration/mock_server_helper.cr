require "socket"
require "time"

MOCK_PORT    = 11435
FIXTURE_PATH = File.expand_path("../../../empaws/.empaws_local/llm_calls.jsonl", __DIR__)
MOCK_BIN     = File.expand_path("../../../llm_mock/bin/llm_mock", __DIR__)

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
