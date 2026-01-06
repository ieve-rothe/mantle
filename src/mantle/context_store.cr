# mantle/context_store.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Context store manages ... context. Not identity, not memory - just manages the ongoing chat and potentially functionality for storing chats when 'finished' and resuming previous chats.

require "json"

module Mantle
  # Contract definition for context store
  #
  # Reminder that immutable types like strings need both the getter and setter defined manually in abstract class, whereas mutable types like Hash don't need the separate setter definition.
  abstract class ContextStore
    abstract def system_prompt : String
    abstract def system_prompt=(system_prompt : String)
    abstract def chat_context : String
    abstract def chat_context=(chat_context : String)
  end

  class EphemeralContextStore < Mantle::ContextStore
    property system_prompt : String
    property chat_context : String = ""

    def initialize(system_prompt : String)
      @system_prompt = system_prompt
      @chat_context += system_prompt
    end

    def system_prompt=(system_prompt : String)
      @chat_context += "\n[SYSTEM UPDATE]: Your core instructions have changed to #{system_prompt}\n"
      @system_prompt = system_prompt
    end
    
    def add_message(label : String, message : String)
      msg_with_label = "[#{label}] #{message}\n"
      @chat_context += msg_with_label
    end

    def clear_context
      @chat_context = system_prompt
    end
  end
end
