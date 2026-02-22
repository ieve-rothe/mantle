# mantle/context_store.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Context store manages ... context. Not identity, not memory - just manages the ongoing chat and potentially functionality for storing chats when 'finished' and resuming previous chats.

require "json"

module Mantle
  # ----------------------------------------------------------------------------
  # Base class context store, not usable by itself.
  class ContextStore
    property system_prompt : String
    getter current_view : String = ""
    property current_num_messages : Int32

    def initialize(system_prompt : String)
      @system_prompt = system_prompt
      @current_view += system_prompt
      @current_num_messages = 0
    end

    def clear_context
      @current_view = system_prompt
    end

    def add_message(label : String, message : String)
      # Implement in specific class
    end

    def prune(num_to_prune : Int32)
      # Implement in specific class.
    end
  end

  # ----------------------------------------------------------------------------
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
      @current_view = "#{@system_prompt}\n#{@messages.join}"
    end
  end

  # ----------------------------------------------------------------------------
  class JSONContextStore < Mantle::ContextStore
    # Data transfer object
    private struct FileData
      include JSON::Serializable
      property system_prompt : String
      property messages : Array(String)

      def initialize(@system_prompt : String, @messages : Array(String))
      end
    end

    def initialize(system_prompt : String, context_file : String)
      super(system_prompt)
      @messages = Deque(String).new
      @context_file = context_file

      load_context_from_json
    end

    def current_view : String
      system_prompt + @messages.join
    end

    def add_message(label : String, message : String)
      msg_with_label = "[#{label}] #{message}\n"
      @messages << msg_with_label
      @current_num_messages = @messages.size
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
        @messages.clear
        data.messages.each { |msg| @messages << msg }
        @current_num_messages = @messages.size
        puts "Loaded context from #{@context_file}"
      rescue e : File::NotFoundError
        save_context_to_json
        puts "Warning: Context file was not found - creating a new one."
      end
    end

    def prune(num_to_prune : Int32) : Array(String)
      pruned_messages = [] of String

      if num_to_prune > @current_num_messages
        count = @current_num_messages
      else
        count = num_to_prune
      end

      count.times do
        pruned_messages << @messages.shift
      end
      save_context_to_json
      return pruned_messages
    end
  end
end
