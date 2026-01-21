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

  class JSONSlidingContextStore < Mantle::ContextStore
    # Data transfer object
    private struct FileData
      include JSON::Serializable
      property system_prompt : String
      property messages : Array(String)

      def initialize(@system_prompt : String, @messages : Array(String))
      end
    end

    # Class properties
    property context_window_discrete #discrete, number of messages to keep, not based on token length

    def initialize(system_prompt : String, context_window_discrete : Int32, context_file : String)
      super(system_prompt)
      @context_window_discrete = context_window_discrete
      @messages = Deque(String).new
      @context_file = context_file

      load_context_from_json
    end

    def chat_context : String
      system_prompt + @messages.join
    end

    def add_message(label : String, message : String)
      msg_with_label = "[#{label}] #{message}\n"
      @messages << msg_with_label
      @messages.shift if @messages.size > @context_window_discrete
      save_context_to_json
    end

    def save_context_to_json : Nil
      data = FileData.new(@system_prompt, @messages.to_a)
      File.write(@context_file, data.to_json)
    end

    def load_context_from_json
      begin
        data = FileData.from_json(File.read(@context_file))
        @system_prompt = data.system_prompt
        all_messages = data.messages
        if all_messages.size > @context_window_discrete
          start_index = all_messages.size - @context_window_discrete
          messages_to_load = all_messages[start_index..-1]
        else
          messages_to_load = all_messages
        end
        @messages.clear
        messages_to_load.each { |msg| @messages << msg}
        puts "Loaded context from #{@context_file}"
      rescue e : File::NotFoundError
        save_context_to_json
        puts "Warning: Context file was not found - creating a new one."
      end
    end
  end
end
