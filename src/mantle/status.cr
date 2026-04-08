# mantle/status.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "set"

module Mantle
  # Allow for consumer to register a callback for handling status updates.
  class_property on_status_update : Proc(Symbol, Nil)?

  def self.emit_status(flag : Symbol)
    on_status_update.try &.call(flag)
  end

  # A singleton bucket for recording status flags and events that
  # the consumer application may want to inspect (e.g. for UI updates).
  module Status
    # Set to store unique status flags
    @@flags = Set(Symbol).new

    # Add a status flag to the bucket.
    def self.add(flag : Symbol)
      @@flags.add(flag)
      Mantle.emit_status(flag)
    end

    # Check if a status flag exists in the bucket.
    def self.has?(flag : Symbol) : Bool
      @@flags.includes?(flag)
    end

    # Remove a specific flag from the bucket.
    def self.remove(flag : Symbol)
      @@flags.delete(flag)
    end

    # Return all current flags as an Array.
    def self.all : Array(Symbol)
      @@flags.to_a
    end

    # Clear all flags from the bucket.
    def self.clear
      @@flags.clear
    end
  end
end
