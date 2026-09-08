# mantle/context_manager.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
module Mantle::Storage
  # Coordinates context routing and consolidation between `ContextStore` and `JSONLayeredMemoryStore`.
  #
  # Responsible for assembling views, tracking token limits, and sliding older context into long-term layered memory.
  class ContextManager
    # Represents the status update callback handler for context management events.
    property on_status : Proc(Symbol, Nil)?

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

    # Creates a context manager with the specified stores, names, and token thresholds.
    def initialize(@context_store : ContextStore,
                   @memory_store : JSONLayeredMemoryStore,
                   @user_name : String,
                   @bot_name : String,
                   @token_target : Int32 = 2000,
                   @token_softmax : Int32 = 3000,
                   @token_hardmax : Int32 = 4000,
                   @strip_thinking_tags : Bool = false,
                   @on_status : Proc(Symbol, Nil)? = nil)
    end

    # Assembles and returns the full conversation prompt window as an array of messages
    # with deterministic spatial placement of Ephemeral Injections.
    #
    # Spatial assembly order:
    # 1. Base system prompt (from context store)
    # 2. System injections (transient system-level constraints, identity nudges, environmental rules)
    # 3. Long-term memory view (from memory store)
    # 4. Pre-history injections (frame/topic context, session status)
    # 5. Conversation history (canonical user/assistant/tool messages)
    # 6. Tail injections (formatting nudges, dev mode triggers, immediate signals)
    def project_view(
      system_injections : Array(Mantle::Message) = [] of Mantle::Message,
      pre_history_injections : Array(Mantle::Message) = [] of Mantle::Message,
      tail_injections : Array(Mantle::Message) = [] of Mantle::Message,
    ) : Array(Mantle::Message)
      messages = [] of Mantle::Message

      # 1. Base system prompt
      base_system_content = @context_store.system_prompt
      unless base_system_content.empty?
        messages << Mantle::Message.new("system", base_system_content)
      end

      # 2. System Injections
      messages.concat(system_injections)

      # 3. Memory view as system message
      memory_view = @memory_store.current_view
      unless memory_view.empty?
        messages << Mantle::Message.new("system", memory_view)
      end

      # 4. Pre-History Injections
      messages.concat(pre_history_injections)

      # 5. Conversation messages from context_store (excluding stored system messages)
      context_messages = @context_store.current_view
      conversation_messages = context_messages.reject { |msg| msg.role == "system" }
      messages.concat(conversation_messages)

      # 6. Tail Injections
      messages.concat(tail_injections)

      messages
    end

    # Convenience overload accepting string injections, wrapping each as a system role message.
    def project_view(
      system_injections : Array(String) = [] of String,
      pre_history_injections : Array(String) = [] of String,
      tail_injections : Array(String) = [] of String,
    ) : Array(Mantle::Message)
      project_view(
        system_injections: system_injections.map { |s| Mantle::Message.new("system", s) },
        pre_history_injections: pre_history_injections.map { |s| Mantle::Message.new("system", s) },
        tail_injections: tail_injections.map { |s| Mantle::Message.new("system", s) },
      )
    end

    # Adds a canonical user message to the context store.
    def add_user_message(content : String)
      @context_store.add_message("User", content)
    end

    # Adds a canonical user message from a Message instance.
    def add_user_message(message : Mantle::Message)
      @context_store.add_message("User", message.content || "")
    end

    # Adds a canonical assistant message to the context store, checking consolidation thresholds.
    def add_assistant_message(content : String, tool_calls : Array(Mantle::Clients::ToolCall)? = nil, check_consolidation : Bool = true)
      processed_msg = @strip_thinking_tags ? Mantle::Support::Text.strip_thinking(content) : content
      @context_store.add_message("Assistant", processed_msg, tool_calls)

      if @context_store.current_num_tokens >= @token_softmax
        @on_status.try &.call(:context_softmax_exceeded)
      end

      if check_consolidation && @context_store.current_num_tokens >= @token_hardmax
        consolidate_memory
      end
    end

    # Adds a canonical assistant message from a Message instance.
    def add_assistant_message(message : Mantle::Message, check_consolidation : Bool = true)
      add_assistant_message(message.content || "", tool_calls: message.tool_calls, check_consolidation: check_consolidation)
    end

    # Handles a user message (delegates to add_user_message).
    def handle_user_message(msg : String)
      add_user_message(msg)
    end

    # Handles a bot response (delegates to add_assistant_message).
    def handle_bot_message(msg : String, tool_calls : Array(Mantle::Clients::ToolCall)? = nil, check_consolidation : Bool = true)
      add_assistant_message(msg, tool_calls: tool_calls, check_consolidation: check_consolidation)
    end

    # Appends a user message from a string to the context store, returning self for chaining.
    def <<(message : String) : self
      add_user_message(message)
      self
    end

    # Appends a typed Message to the context store, preserving role and metadata, returning self for chaining.
    def <<(message : Mantle::Message) : self
      normalized = message.role.downcase
      case normalized
      when "user", "username"
        add_user_message(message.content || "")
      when "bot", "botname", "assistant"
        add_assistant_message(message)
      else
        add_message(message.role, message.content || "", message.tool_calls, message.tool_call_id)
      end
      self
    end

    # Adds a message to the context with a specific *role*, *content*, and optional tool calls, optionally checking consolidation.
    def add_message(role : String, content : String, tool_calls : Array(Mantle::Clients::ToolCall)? = nil, tool_call_id : String? = nil, check_consolidation : Bool = true)
      @context_store.add_message(role, content, tool_calls, tool_call_id)

      if @context_store.current_num_tokens >= @token_softmax
        @on_status.try &.call(:context_softmax_exceeded)
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
      @on_status.try &.call(:memory_consolidation)

      Mantle::Log.info { "Context hit tokens #{@context_store.current_num_tokens} (threshold: #{@token_hardmax}). Consolidating Context -> Memory. Target context tokens: #{@token_target}." }

      pruned_messages = @context_store.prune_to_tokens(@token_target)

      if pruned_messages && pruned_messages.size >= 1
        # Convert message hashes to formatted strings for memory store
        formatted_messages = pruned_messages.map do |msg|
          role_label = msg.role == "user" ? @user_name : @bot_name
          content = msg.content
          if (content.nil? || content.empty?) && (tcs = msg.tool_calls)
            content = "Called tools: " + tcs.map { |tc| tc.function.name }.join(", ")
          end
          "[#{role_label}] #{content}\n"
        end
        @memory_store.ingest(formatted_messages)
      else
        Mantle::Log.error { "Tried to ingest to memory store with an invalid pruned_messages array" }
      end
    end

    # Consolidates all conversation messages in the context store into long-term memory
    # and clears the context store (0 tokens of conversation history left).
    def consolidate_all_to_memory(is_frame_switch : Bool = false)
      @on_status.try &.call(:memory_consolidation)

      num_messages = @context_store.current_num_messages
      num_tokens = @context_store.current_num_tokens

      if is_frame_switch
        Mantle::Log.info { "Frame switch triggered: Consolidating all #{num_messages} messages (#{num_tokens} tokens) of target topic context into memory cascade." }
      else
        Mantle::Log.info { "Consolidating all #{num_messages} messages (#{num_tokens} tokens) of context into memory cascade." }
      end

      # Prune everything down to 0 tokens of conversation history
      pruned_messages = @context_store.prune_to_tokens(0)

      if pruned_messages && pruned_messages.size >= 1
        # Convert message hashes to formatted strings for memory store
        formatted_messages = pruned_messages.map do |msg|
          role_label = msg.role == "user" ? @user_name : @bot_name
          content = msg.content
          if (content.nil? || content.empty?) && (tcs = msg.tool_calls)
            content = "Called tools: " + tcs.map { |tc| tc.function.name }.join(", ")
          end
          "[#{role_label}] #{content}\n"
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

    # Returns whether the last conversation turn in context_store is replayable.
    def last_turn_replayable? : Bool
      @context_store.last_turn_replayable?
    end

    # Returns the last user message if the last turn is replayable.
    def last_user_message : Mantle::Message?
      @context_store.last_user_message
    end

    # Returns the last bot message if the last turn is replayable.
    def last_bot_message : Mantle::Message?
      @context_store.last_bot_message
    end

    # Edits the content of the last bot message in context_store in-place.
    def edit_last_bot_message(new_content : String) : Bool
      @context_store.edit_last_bot_message(new_content)
    end

    # Removes the last bot response and user prompt from context_store for replay.
    def pop_last_turn_for_replay : String?
      @context_store.pop_last_turn_for_replay
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
        @memory_store.ingest([] of String) # Trigger cascade without adding new items
      end

      # 2. Ensure all data is flushed to disk
      # (save_memories_to_json is called by cascade, but call it explicitly to be safe)
      @memory_store.ingest([] of String)

      # 3. Reassign to new stores
      @context_store = new_context
      @memory_store = new_memory

      # Token tracking is delegated to the stores, so no need to reset it manually
    end
  end
end
