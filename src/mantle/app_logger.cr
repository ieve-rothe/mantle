# mantle/app_logger.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle
  # A simple app-wide logger for debugging Mantle itself.
  # Typically only enabled if DEBUG_MANTLE is set, but can be configured manually.
  class AppLogger
    property enabled : Bool
    property io : IO

    def initialize(@io : IO = STDOUT)
      @enabled = ENV.has_key?("DEBUG_MANTLE")
    end

    def info(message : String? = nil, &)
      if @enabled
        content = message || yield
        @io.puts "[Mantle INFO] #{content}"
      end
    end

    def info(message : String)
      @io.puts "[Mantle INFO] #{message}" if @enabled
    end

    def debug(message : String? = nil, &)
      if @enabled
        content = message || yield
        @io.puts "[Mantle DEBUG] #{content}"
      end
    end

    def debug(message : String)
      @io.puts "[Mantle DEBUG] #{message}" if @enabled
    end

    def error(message : String? = nil, &)
      if @enabled
        content = message || yield
        @io.puts "[Mantle ERROR] #{content}"
      end
    end

    def error(message : String)
      @io.puts "[Mantle ERROR] #{message}" if @enabled
    end

    def warn(message : String? = nil, &)
      if @enabled
        content = message || yield
        @io.puts "[Mantle WARN] #{content}"
      end
    end

    def warn(message : String)
      @io.puts "[Mantle WARN] #{message}" if @enabled
    end
  end

  Log = AppLogger.new
end
