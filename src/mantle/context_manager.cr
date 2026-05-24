# mantle/context_manager.cr
# Copyright (C) 2026 Cam Carroll
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
    property token_target : Int32
    property token_softmax : Int32
    property token_hardmax : Int32
    property strip_thinking_tags : Bool

    def initialize(@context_store : ContextStore,
                   @memory_store : JSONLayeredMemoryStore,
                   @user_name : String,
                   @bot_name : String,
                   @token_target : Int32 = 2000,
                   @token_softmax : Int32 = 3000,
                   @token_hardmax : Int32 = 4000,
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

      if @context_store.current_num_tokens >= @token_softmax
        Mantle.emit_status(:context_softmax_exceeded)
      end

      if check_consolidation && @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Add a message to context with a specific role, optionally deferring consolidation check
    def add_message(role : String, content : String, check_consolidation : Bool = true)
      @context_store.add_message(role, content)

      if @context_store.current_num_tokens >= @token_softmax
        Mantle.emit_status(:context_softmax_exceeded)
      end

      if check_consolidation && @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Manually trigger consolidation check (for use at turn boundaries)
    def check_and_consolidate
      if @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Explicitly check for soft consolidation (can be triggered by user application when idle)
    def check_and_consolidate_soft
      if @context_store.current_num_tokens >= @token_softmax
        consolidate_memory
      end
    end

    def consolidate_memory
      Mantle.emit_status(:memory_consolidation)

      Mantle::Log.info { "Context hit tokens #{@context_store.current_num_tokens} (threshold: #{@token_hardmax}). Consolidating Context -> Memory. Target context tokens: #{@token_target}." }

      pruned_messages = @context_store.prune_to_tokens(@token_target)

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

    def clear_context
      @context_store.clear
    end

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

    private def strip_thinking(msg : String) : String
      # Remove <think>...</think> blocks and their contents
      # Uses regex with multiline flag to handle thinking blocks that span multiple lines
      msg.gsub(/<think>.*?<\/think>/m, "")
    end
  end
end
