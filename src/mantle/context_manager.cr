# mantle/context_manager.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Coordinates context routing from flow to ContextStore and MemoryStore

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

    def initialize(@context_store : ContextStore,
                   @memory_store : JSONLayeredMemoryStore,
                   @user_name : String,
                   @bot_name : String,
                   @msg_target : Int32 = 4,
                   @msg_hardmax : Int32 = 10)
    end

    def current_view
      memory_view = @memory_store.current_view
      chat_context = @context_store.current_view
      return  memory_view + chat_context
    end

    def handle_user_message(msg : String)
      @context_store.add_message(@user_name, msg)

      # Later - Don't write tests for these future functions yet.
      # potentially check for special context command flags?
      # (such as, clear context, replay last turn without changes, replay last turn with changes)
    end

    def handle_bot_message(msg : String)
      @context_store.add_message(@bot_name, msg)

      if @context_store.current_num_messages >= @msg_hardmax
        puts "Running memory consolidation, please wait..."
        consolidate_memory
      end

      # Future functionality (don't write tests yet):
      # Check for msg_softmax, set a flag for dreaming loop.
    end

    def consolidate_memory
      # If we're at msg_hardmax, prune msg_hardmax - msg_target messages from context_store using the .prune method, then we pump those messages into memory_store.ingest()
      num_to_prune = @msg_hardmax - @msg_target
      if num_to_prune == nil || num_to_prune <= 1
        # Error, num_to_prune not valid
        puts "Error - Tried to prune context by an invalid number of messages."
      else
        pruned_messages = @context_store.prune(num_to_prune)
        if pruned_messages && pruned_messages.size >= 1
          @memory_store.ingest(pruned_messages)
        else
          puts "Error - Tried to ingest to memory store with an invalid pruned_messages array"
        end
      end
    end

    def clear_context
      @current_view = system_prompt
    end
  end
end
