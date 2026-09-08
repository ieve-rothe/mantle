# mantle.cr
# Main entry point for library
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "log"
require "./mantle/support/*"
require "./mantle/clients/*"
require "./mantle/tools/*"
require "./mantle/storage/*"
require "./mantle/steps/*"
require "./mantle/subagents/*"
require "./mantle/session"

# Represents the core module of the Mantle LLM agent library.
module Mantle
  # Provides the default logger for the Mantle library.
  #
  # Consumer applications should configure this via Crystal's built-in Log setup:
  #
  # ```
  # ::Log.setup do |c|
  #   backend = ::Log::IOBackend.new(io: File.new("app.log", "a"))
  #   c.bind("mantle", :debug, backend)
  # end
  # ```
  Log = ::Log.for("mantle")
end
