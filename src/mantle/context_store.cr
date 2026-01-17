# mantle/context_store.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Context store manages ... context. Not identity, not memory - just manages the ongoing chat and potentially functionality for storing chats when 'finished' and resuming previous chats.

require "json"

module Mantle
  # Base class context store, not usable by itself.
  class ContextStore
    property system_prompt : String
    getter chat_context : String = ""

    def initialize(system_prompt : String)
      @system_prompt = system_prompt
      @chat_context += system_prompt
    end

    def clear_context
      @chat_context = system_prompt
    end

    def add_message(label : String, message : String)
      # Implement in specific class
    end
  end

  class EphemeralContextStore < Mantle::ContextStore
    def system_prompt=(system_prompt : String)
      @chat_context += "\n[SYSTEM UPDATE]: Your core instructions have changed to #{system_prompt}\n"
      @system_prompt = system_prompt
    end
    
    def add_message(label : String, message : String)
      msg_with_label = "[#{label}] #{message}\n"
      @chat_context += msg_with_label
    end
  end

  class EphemeralSlidingContextStore < Mantle::ContextStore
    property messages_to_keep

    def initialize(system_prompt : String, messages_to_keep : Int32)
      super(system_prompt)
      @messages_to_keep = messages_to_keep
      @messages = Deque(String).new
    end

    def add_message(label : String, message : String)
      msg_with_label = "[#{label}] #{message}\n"
      @messages << msg_with_label
      @messages.shift if @messages.size > @messages_to_keep
      @chat_context = "#{@system_prompt}\n#{@messages.join}"
    end
  end
end
