# mantle/status.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "set"

module Mantle
  # Allows the consumer to register a callback for handling status updates.
  class_property on_status_update : Proc(Symbol, Nil)?

  # Emits a status update *flag* to the registered callback if one exists.
  #
  # Italicized parameter: *flag*
  def self.emit_status(flag : Symbol)
    on_status_update.try &.call(flag)
  end
end
