# mantle/status.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "set"

module Mantle
  # A singleton bucket for recording status flags and events that
  # the consumer application may want to inspect (e.g. for UI updates).
  module Status
    # Set to store unique status flags
    @@flags = Set(Symbol).new

    # Add a status flag to the bucket.
    def self.add(flag : Symbol)
      @@flags.add(flag)
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
