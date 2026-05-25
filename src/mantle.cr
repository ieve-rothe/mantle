# mantle.cr
# Main entry point for library
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./mantle/flow"
require "./mantle/context_manager"
require "./mantle/context_store"
require "./mantle/memory_store"
require "./mantle/squishifiers"
require "./mantle/client"
require "./mantle/logger"
require "./mantle/markdown_formatter"

# Represents the core module of the Mantle LLM agent library.
module Mantle
  # Represents the current version of the Mantle library.
  VERSION = "0.1.0"
end
