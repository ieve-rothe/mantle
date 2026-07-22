# mantle/support/log_context.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "log"
require "uuid"

module Mantle
  # Fiber-safe context helper for setting and propagating sequence IDs for LLM call logging.
  module LogContext
    # Returns the current fiber's sequence_id if set in Log.context metadata.
    def self.sequence_id : String?
      Log.context.metadata[:sequence_id]?.try(&.as_s)
    end

    # Sets the sequence_id for the current fiber.
    def self.sequence_id=(id : String?)
      if id
        Log.context.set(sequence_id: id)
      end
    end

    # Runs the block with sequence_id set for the current fiber.
    # Restores the original sequence_id after the block completes.
    def self.with_sequence_id(id : String, &block)
      Log.with_context do
        Log.context.set(sequence_id: id)
        yield
      end
    end
  end
end
