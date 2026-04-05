# mantle/app_logger.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "log"

module Mantle
  # Default logger for the Mantle library
  #
  # Consumer applications should configure this via Crystal's built-in Log setup:
  # ```
  # ::Log.setup do |c|
  #   backend = ::Log::IOBackend.new(io: File.new("app.log", "a"))
  #   c.bind("mantle", :debug, backend)
  # end
  # ```
  Log = ::Log.for("mantle")
end
