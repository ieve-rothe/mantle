# mantle/context_manager.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Coordinates context routing from flow to ContextStore and MemoryStore

require "./app_logger"
require "./status"

module Mantle
  # Responsible for coordinating context and memory.
  class ContextManager
    property context_store : ContextStore
    property memory_store : JSONLayeredMemoryStore
    property user_name : String
    property bot_name : String
    property msg_target : Int32
    # property msg_softmax : Int32 # (Not implemented yet)
    property msg_hardmax : Int32
    property strip_thinking_tags : Bool

    def initialize(@context_store : ContextStore,
                   @memory_store : JSONLayeredMemoryStore,
                   @user_name : String,
                   @bot_name : String,
                   @msg_target : Int32 = 4,
                   @msg_hardmax : Int32 = 10,
                   @strip_thinking_tags : Bool = false)
    end

    def current_view : Array(Hash(String, String))
      messages = [] of Hash(String, String)

      # Build system message combining system prompt and memory
      system_content = @context_store.system_prompt
      memory_view = @memory_store.current_view

      if !memory_view.empty?
        system_content += "\n\n" + memory_view
      end

      # Add system message if there's content
      unless system_content.empty?
        messages << {"role" => "system", "content" => system_content}
      end

      # Get conversation messages from context_store (skip the system message it includes)
      context_messages = @context_store.current_view
      conversation_messages = context_messages.select { |msg| msg["role"] != "system" }
      messages.concat(conversation_messages)

      return messages
    end

    def handle_user_message(msg : String)
      # Always use "User" label for normalization, not custom user_name
      @context_store.add_message("User", msg)

      # Later - Don't write tests for these future functions yet.
      # potentially check for special context command flags?
      # (such as, clear context, replay last turn without changes, replay last turn with changes)
    end

    def handle_bot_message(msg : String, check_consolidation : Bool = true)
      # Strip thinking tags if enabled
      processed_msg = @strip_thinking_tags ? strip_thinking(msg) : msg

      # Always use "Assistant" label for normalization, not custom bot_name
      @context_store.add_message("Assistant", processed_msg)

      if check_consolidation && @context_store.current_num_messages >= @msg_hardmax
        consolidate_memory
      end

      # Future functionality (don't write tests yet):
      # Check for msg_softmax, set a flag for dreaming loop.
    end

    # Add a message to context with a specific role, optionally deferring consolidation check
    def add_message(role : String, content : String, check_consolidation : Bool = true)
      @context_store.add_message(role, content)

      if check_consolidation && @context_store.current_num_messages >= @msg_hardmax
        consolidate_memory
      end
    end

    # Manually trigger consolidation check (for use at turn boundaries)
    def check_and_consolidate
      if @context_store.current_num_messages >= @msg_hardmax
        consolidate_memory
      end
    end

    def consolidate_memory
      Mantle::Status.add(:memory_consolidation)
      # If we're at msg_hardmax, prune msg_hardmax - msg_target messages from context_store using the .prune method, then we pump those messages into memory_store.ingest()
      num_to_prune = @msg_hardmax - @msg_target

      Mantle::Log.info { "Context hit size #{@context_store.current_num_messages} (threshold: #{@msg_hardmax}). Consolidating Context -> Memory. Target context size: #{@msg_target}. Pruning #{num_to_prune} messages." }

      if num_to_prune == nil || num_to_prune <= 1
        # Error, num_to_prune not valid
        Mantle::Log.error { "Tried to prune context by an invalid number of messages." }
      else
        pruned_messages = @context_store.prune(num_to_prune)
        if pruned_messages && pruned_messages.size >= 1
          # Convert message hashes to formatted strings for memory store
          formatted_messages = pruned_messages.map do |msg|
            role_label = msg["role"] == "user" ? @user_name : @bot_name
            "[#{role_label}] #{msg["content"]}\n"
          end
          @memory_store.ingest(formatted_messages)
        else
          Mantle::Log.error { "Tried to ingest to memory store with an invalid pruned_messages array" }
        end
      end
    end

    def clear_context
      @context_store.clear
    end

    private def strip_thinking(msg : String) : String
      # Remove <think>...</think> blocks and their contents
      # Uses regex with multiline flag to handle thinking blocks that span multiple lines
      msg.gsub(/<think>.*?<\/think>/m, "")
    end
  end
end
