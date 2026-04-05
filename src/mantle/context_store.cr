# mantle/context_store.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Context store manages ... context. Not identity, not memory - just manages the ongoing chat and potentially functionality for storing chats when 'finished' and resuming previous chats.

require "json"
require "./app_logger"
require "./status"

module Mantle
  # ----------------------------------------------------------------------------
  # Base class context store, not usable by itself.
  class ContextStore
    property system_prompt : String
    property current_num_messages : Int32

    def initialize(system_prompt : String)
      @system_prompt = system_prompt
      @current_num_messages = 0
    end

    # Returns messages in chat format: Array(Hash(String, String))
    # Each hash has "role" and "content" keys
    def current_view : Array(Hash(String, String))
      # Implement in specific class
      [] of Hash(String, String)
    end

    def add_message(label : String, message : String)
      # Implement in specific class
    end

    def prune(num_to_prune : Int32)
      # Implement in specific class.
    end

    # Normalize label to valid chat role
    protected def normalize_role(label : String) : String
      normalized = label.downcase
      case normalized
      when "user", "username"
        "user"
      when "bot", "botname", "assistant"
        "assistant"
      when "system"
        "system"
      when "tool"
        "tool"
      else
        raise ArgumentError.new("Invalid role label: #{label}. Must be user, assistant, system, or tool.")
      end
    end

    # Validate that role is one of the allowed values
    protected def validate_role(role : String)
      unless ["user", "assistant", "system", "tool"].includes?(role)
        raise ArgumentError.new("Invalid role: #{role}. Must be user, assistant, system, or tool.")
      end
    end
  end

  # ----------------------------------------------------------------------------
  class EphemeralSlidingContextStore < Mantle::ContextStore
    property messages_to_keep

    def initialize(system_prompt : String, messages_to_keep : Int32)
      super(system_prompt)
      @messages_to_keep = messages_to_keep
      @messages = Deque(Hash(String, String)).new
    end

    def current_view : Array(Hash(String, String))
      result = [] of Hash(String, String)
      # Add system prompt as first message if present
      result << {"role" => "system", "content" => @system_prompt} unless @system_prompt.empty?
      # Add conversation messages
      result.concat(@messages.to_a)
      result
    end

    def add_message(label : String, message : String)
      role = normalize_role(label)
      @messages << {"role" => role, "content" => message}
      @messages.shift if @messages.size > @messages_to_keep
      @current_num_messages = @messages.size
    end
  end

  # ----------------------------------------------------------------------------
  class JSONContextStore < Mantle::ContextStore
    # Data transfer object
    private struct FileData
      include JSON::Serializable
      property system_prompt : String
      property messages : Array(Hash(String, String))

      def initialize(@system_prompt : String, @messages : Array(Hash(String, String)))
      end
    end

    def initialize(system_prompt : String, context_file : String)
      super(system_prompt)
      @messages = Deque(Hash(String, String)).new
      @context_file = context_file

      load_context_from_json
    end

    def current_view : Array(Hash(String, String))
      result = [] of Hash(String, String)
      # Add system prompt as first message if present
      result << {"role" => "system", "content" => @system_prompt} unless @system_prompt.empty?
      # Add conversation messages
      result.concat(@messages.to_a)
      result
    end

    def add_message(label : String, message : String)
      role = normalize_role(label)
      @messages << {"role" => role, "content" => message}
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
        data.messages.each do |msg|
          # Validate roles when loading
          validate_role(msg["role"])
          @messages << msg
        end
        @current_num_messages = @messages.size
        Mantle::Log.info { "Loaded context from #{@context_file}" }
      rescue e : File::NotFoundError
        save_context_to_json
        Mantle::Log.warn { "Context file was not found - creating a new one." }
        Mantle::Status.add(:new_context_file)
      end
    end

    def prune(num_to_prune : Int32) : Array(Hash(String, String))
      pruned_messages = [] of Hash(String, String)

      if num_to_prune > @current_num_messages
        count = @current_num_messages
      else
        count = num_to_prune
      end

      count.times do
        pruned_messages << @messages.shift
      end
      @current_num_messages = @messages.size
      save_context_to_json
      return pruned_messages
    end
  end
end
