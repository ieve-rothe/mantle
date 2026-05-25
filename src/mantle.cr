# mantle.cr
# Main entry point for library
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./mantle/support/*"
require "./mantle/clients/*"
require "./mantle/tools/*"
require "./mantle/storage/*"
require "./mantle/flows/*"

# Represents the core module of the Mantle LLM agent library.
module Mantle
  # Represents the current version of the Mantle library.
  VERSION = "0.1.0"
end
