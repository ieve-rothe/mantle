# mantle.cr
# Main entry point for library
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./mantle/flow"
require "./mantle/context_manager"
require "./mantle/context_store"
require "./mantle/memory_store"
require "./mantle/squishifiers"
require "./mantle/client"
require "./mantle/logger"
require "./mantle/markdown_formatter"

module Mantle
  VERSION = "0.1.0"
end
