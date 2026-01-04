# mantle/context_store.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Abstract class for context store

require "json"

module Mantle
  # Contract definition for context store
  #
  # This is to be implemented by the consumer application. Might be backed by a JSON config file or just in-memory data.
  # Reminder that immutable types like strings need both the getter and setter defined manually in abstract class, whereas mutable types like Hash don't need the separate setter definition.
  abstract class ContextStore
    abstract def system_prompt : String
    abstract def system_prompt=(system_prompt : String)
    abstract def chat_context : String
    abstract def chat_context=(chat_context : String)
    abstract def scratchpad : Hash(String, JSON::Any)
  end
end
