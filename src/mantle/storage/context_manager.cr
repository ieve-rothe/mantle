# mantle/context_manager.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Coordinates context routing from flow to ContextStore and MemoryStore

require "../support/app_logger"
require "../support/status"

module Mantle::Storage
  # Coordinates context routing and consolidation between `ContextStore` and `JSONLayeredMemoryStore`.
  #
  # Responsible for assembling views, tracking token limits, and sliding older context into long-term layered memory.
  class ContextManager
    # Represents the active `ContextStore` instance.
    property context_store : ContextStore

    # Represents the active `JSONLayeredMemoryStore` instance.
    property memory_store : JSONLayeredMemoryStore

    # Represents the display name for user messages in memory logs.
    property user_name : String

    # Represents the display name for bot messages in memory logs.
    property bot_name : String

    # Represents the target token count when pruning/consolidating context.
    property token_target : Int32

    # Represents the soft threshold above which a warning status is emitted.
    property token_softmax : Int32

    # Represents the hard threshold at which context is consolidated into memory.
    property token_hardmax : Int32

    # Represents whether to strip `<think>...</think>` tags from bot responses before storing them.
    property strip_thinking_tags : Bool

    # :nodoc:
    @pending_invisible_append : String? = nil

    # Creates a context manager with the specified stores, names, and token thresholds.
    def initialize(@context_store : ContextStore,
                   @memory_store : JSONLayeredMemoryStore,
                   @user_name : String,
                   @bot_name : String,
                   @token_target : Int32 = 2000,
                   @token_softmax : Int32 = 3000,
                   @token_hardmax : Int32 = 4000,
                   @strip_thinking_tags : Bool = false)
    end

    # Assembles and returns the full conversation context as an array of messages.
    #
    # Incorporates the base system prompt, optional *ephemeral_blocks*, long-term memory view,
    # chat history, and applies any pending invisible appends.
    def current_view(ephemeral_blocks : Array(String) = [] of String) : Array(Hash(String, String))
      messages = [] of Hash(String, String)

      # 1. Base system prompt (without memory yet)
      base_system_content = @context_store.system_prompt
      unless base_system_content.empty?
        messages << {"role" => "system", "content" => base_system_content}
      end

      # 2. Ephemeral blocks as separate system messages
      ephemeral_blocks.each do |block|
        messages << {"role" => "system", "content" => block}
      end

      # 3. Memory view as system message
      memory_view = @memory_store.current_view
      if !memory_view.empty?
        messages << {"role" => "system", "content" => memory_view}
      end

      # 4. Get conversation messages from context_store (skip the system message it includes)
      context_messages = @context_store.current_view
      conversation_messages = context_messages.select { |msg| msg["role"] != "system" }
      messages.concat(conversation_messages)

      # 5. Apply pending invisible append to the last user message if present
      if pending_append = @pending_invisible_append
        # Find the index of the last user message
        last_user_index = nil
        messages.each_with_index do |msg, idx|
          if msg["role"] == "user"
            last_user_index = idx
          end
        end

        if last_user_index
          # Create a new hash with the appended content (don't modify original)
          original_msg = messages[last_user_index]
          messages[last_user_index] = {
            "role"    => original_msg["role"],
            "content" => original_msg["content"] + pending_append,
          }
        end

        # Clear the pending append after applying it
        @pending_invisible_append = nil
      end

      return messages
    end

    # Handles a user message *msg*, optionally storing *invisible_append* to be applied in the next view.
    def handle_user_message(msg : String, invisible_append : String? = nil)
      # Always use "User" label for normalization, not custom user_name
      # Only store the visible msg to context_store
      @context_store.add_message("User", msg)

      # Store the invisible append for next current_view call
      @pending_invisible_append = invisible_append
    end

    # Handles a bot response *msg*, optionally triggering context consolidation if *check_consolidation* is true.
    def handle_bot_message(msg : String, check_consolidation : Bool = true)
      # Strip thinking tags if enabled
      processed_msg = @strip_thinking_tags ? strip_thinking(msg) : msg

      # Always use "Assistant" label for normalization, not custom bot_name
      @context_store.add_message("Assistant", processed_msg)

      if @context_store.current_num_tokens >= @token_softmax
        Mantle.emit_status(:context_softmax_exceeded)
      end

      if check_consolidation && @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Adds a message to the context with a specific *role* and *content*, optionally checking consolidation.
    def add_message(role : String, content : String, check_consolidation : Bool = true)
      @context_store.add_message(role, content)

      if @context_store.current_num_tokens >= @token_softmax
        Mantle.emit_status(:context_softmax_exceeded)
      end

      if check_consolidation && @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Manually triggers a hard consolidation check (for use at turn boundaries).
    def check_and_consolidate
      if @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Explicitly checks for soft consolidation (can be triggered by user application when idle).
    def check_and_consolidate_soft
      if @context_store.current_num_tokens >= @token_softmax
        consolidate_memory
      end
    end

    # Performs the consolidation process by pruning context and ingesting pruned messages into the memory store.
    def consolidate_memory
      Mantle.emit_status(:memory_consolidation)

      Mantle::Support::Log.info { "Context hit tokens #{@context_store.current_num_tokens} (threshold: #{@token_hardmax}). Consolidating Context -> Memory. Target context tokens: #{@token_target}." }

      pruned_messages = @context_store.prune_to_tokens(@token_target)

      if pruned_messages && pruned_messages.size >= 1
        # Convert message hashes to formatted strings for memory store
        formatted_messages = pruned_messages.map do |msg|
          role_label = msg["role"] == "user" ? @user_name : @bot_name
          "[#{role_label}] #{msg["content"]}\n"
        end
        @memory_store.ingest(formatted_messages)
      else
        Mantle::Support::Log.error { "Tried to ingest to memory store with an invalid pruned_messages array" }
      end
    end

    # Consolidates all conversation messages in the context store into long-term memory
    # and clears the context store (0 tokens of conversation history left).
    def consolidate_all_to_memory(is_frame_switch : Bool = false)
      Mantle.emit_status(:memory_consolidation)

      num_messages = @context_store.current_num_messages
      num_tokens = @context_store.current_num_tokens

      if is_frame_switch
        Mantle::Support::Log.info { "Frame switch triggered: Consolidating all #{num_messages} messages (#{num_tokens} tokens) of target topic context into memory cascade." }
      else
        Mantle::Support::Log.info { "Consolidating all #{num_messages} messages (#{num_tokens} tokens) of context into memory cascade." }
      end

      # Prune everything down to 0 tokens of conversation history
      pruned_messages = @context_store.prune_to_tokens(0)

      if pruned_messages && pruned_messages.size >= 1
        # Convert message hashes to formatted strings for memory store
        formatted_messages = pruned_messages.map do |msg|
          role_label = msg["role"] == "user" ? @user_name : @bot_name
          "[#{role_label}] #{msg["content"]}\n"
        end
        @memory_store.ingest(formatted_messages)
      end

      # Clear context store to be absolutely sure it is clean
      @context_store.clear
    end

    # Clears the active context store.
    def clear_context
      @context_store.clear
    end

    # Updates the system prompt in the active context store with *new_prompt*.
    def update_system_prompt(new_prompt : String)
      @context_store.update_system_prompt(new_prompt)
    end

    # Returns stats for token tracking and memory layers.
    def stats : NamedTuple(
      context_tokens: Int32,
      context_softmax: Int32,
      context_hardmax: Int32,
      memory_layers: Int32,
      memory_layer_stats: Array(NamedTuple(layer: Int32, tokens: Int32, capacity: Int32)))
      memory_stats = [] of NamedTuple(layer: Int32, tokens: Int32, capacity: Int32)
      layer_count = @memory_store.layers.size

      (0...layer_count).each do |i|
        memory_stats << {
          layer:    i,
          tokens:   @memory_store.current_num_tokens(i),
          capacity: @memory_store.layer_token_capacity,
        }
      end

      {
        context_tokens:     @context_store.current_num_tokens,
        context_softmax:    @token_softmax,
        context_hardmax:    @token_hardmax,
        memory_layers:      layer_count,
        memory_layer_stats: memory_stats,
      }
    end

    # Hot-swaps the active *new_context* and *new_memory* stores safely.
    #
    # Flushes pending data from old stores before swapping.
    def flush_and_swap(new_context : ContextStore, new_memory : JSONLayeredMemoryStore)
      # 1. Force the outgoing memory store to process any remaining ingest_pending items
      if !@memory_store.ingest_pending.empty?
        @memory_store.ingest([] of String)  # Trigger cascade without adding new items
      end

      # 2. Ensure all data is flushed to disk
      # (save_memories_to_json is called by cascade, but call it explicitly to be safe)
      @memory_store.ingest([] of String)

      # 3. Reassign to new stores
      @context_store = new_context
      @memory_store = new_memory

      # 4. Clear any pending invisible append from old context
      @pending_invisible_append = nil

      # Token tracking is delegated to the stores, so no need to reset it manually
    end

    # :nodoc:
    private def strip_thinking(msg : String) : String
      # Remove <think>...</think> blocks and their contents
      # Uses regex with multiline flag to handle thinking blocks that span multiple lines
      msg.gsub(/<think>.*?<\/think>/m, "")
    end
  end
end
