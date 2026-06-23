# mantle/memory_store.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Manages memory for the agent.

require "json"
require "../support/app_logger"
require "../support/status"

module Mantle::Storage
  # Maybe write a base class once we have an implementation for Layered and then are going to add another type of memorystore

  # Represents a layered memory store that persists memories to a JSON file.
  #
  # Manages the agent's long-term memory using hierarchical layers that consolidate when capacity is reached.
  class JSONLayeredMemoryStore
    # Represents the path to the JSON file where memories are stored.
    property memory_file : String

    # Represents the target token count when consolidating a layer.
    property layer_token_target : Int32

    # Represents the token capacity limit for each memory layer.
    property layer_token_capacity : Int32

    # Represents the proc used to summarize and compress messages.
    property squishifier : Proc(Array(String), String)

    # Represents the queue of messages waiting to be ingested into memory layer 0.
    property ingest_pending : Array(String) = [] of String

    # Represents the collection of memory layers.
    property layers : Array(Array(String)) = [] of Array(String)

    # Creates a memory store using *memory_file*, *layer_token_capacity*, *layer_token_target*, and *squishifier*.
    #
    # Raises `Exception` if the configuration constraints are not met.
    def initialize(@memory_file,
                   @layer_token_capacity,
                   @layer_token_target,
                   @squishifier)
      if layer_token_target >= layer_token_capacity
        raise Exception.new("layer_token_capacity must be greater than layer_token_target")
      elsif layer_token_target <= 0
        raise Exception.new("layer_token_target must be positive")
      end
      load_memories_from_json
    end

    # Returns the number of tokens in the memory layer at *layer_index*.
    def current_num_tokens(layer_index : Int32) : Int32
      return 0 if layer_index >= @layers.size || layer_index < 0
      @layers[layer_index].sum { |msg| msg.size // 4 }
    end

    # Returns a formatted string representation of all active memory layers.
    def current_view : String
      return "" if @layers.empty? || @layers.all? { |layer| layer.empty? }

      view = String::Builder.new

      @layers.reverse_each.with_index do |layer, index|
        next if layer.empty?
        actual_layer_num = @layers.size - 1 - index
        view << "=== Memory Layer #{actual_layer_num} ===\n"
        layer.each do |memory|
          view << memory
          view << "\n" unless memory.ends_with?("\n")
        end
        view << "\n"
      end

      return view.to_s
    end

    # Ingests an array of *messages* into the memory store, triggering cascading consolidation where needed.
    def ingest(messages : Array(String)) : Nil
      @ingest_pending.concat(messages)
      save_memories_to_json

      cascade(-1) # layer -1 indicates input to layer 0, ie incoming context
    end

    # Checks all memory layers and triggers cascading consolidation on any that exceed capacity.
    #
    # Can be called explicitly by user application when idle.
    def check_and_consolidate
      @layers.each_with_index do |layer, index|
        if current_num_tokens(index) >= @layer_token_capacity
          cascade(index)
        end
      end
    end

    # Private -------------------------------------------------------------

    private def cascade(current_layer_index : Int32) : Nil
      # Prevent infinite recursion - reasonable max layer depth
      if current_layer_index > 50
        Mantle::Support::Log.warn { "Maximum layer depth (50) reached" }
        return
      end

      target_layer_index = current_layer_index + 1

      if current_layer_index == -1
        source = @ingest_pending
      else
        source = @layers[current_layer_index]
      end

      if @layers.size <= target_layer_index
        @layers << [] of String
      end

      processed_count = 0

      begin
        # For layer -1, we process everything.
        # For other layers, we process until the remaining tokens in source are <= @layer_token_target
        while (current_layer_index == -1 && source.size - processed_count > 0) ||
              (current_layer_index != -1 && calculate_tokens(source[processed_count..-1]) > @layer_token_target)
          # Before adding, check if target layer is already at capacity
          # If so, consolidate it first to make room
          while current_num_tokens(target_layer_index) >= @layer_token_capacity
            cascade(target_layer_index)
            # If consolidation didn't free up space, we can't proceed
            break if current_num_tokens(target_layer_index) >= @layer_token_capacity
          end

          # If target is still at capacity after consolidation, we can't add more
          if current_num_tokens(target_layer_index) >= @layer_token_capacity
            Mantle::Support::Log.warn { "Layer #{target_layer_index} still at capacity after consolidation" }
            return
          end

          if current_layer_index != -1
            Mantle.emit_status(:memory_consolidation)
            Mantle::Support::Log.info { "Memory Layer #{current_layer_index} hit capacity (#{@layer_token_capacity} tokens). Consolidating Layer #{current_layer_index} -> Layer #{target_layer_index}. Target size: #{@layer_token_target} tokens." }
          end

          if current_layer_index == -1
            chunk_size = source.size - processed_count
          else
            chunk_size = calculate_chunk_size_to_reach_target(source[processed_count..-1], @layer_token_target)
          end

          chunk = source[processed_count, chunk_size]

          begin
            summary = @squishifier.call(chunk)
            # Strip thinking tags from the squishified summary
            summary = strip_thinking(summary)
            # If no exception from squishifier, then successful response from LLM
            timestamp = Time.utc.to_s("%Y-%m-%d %H:%M")
            @layers[target_layer_index] << "[#{timestamp}] #{summary}"

            processed_count += chunk_size
          rescue ex
            Mantle::Support::Log.error { "Squishifier failed at layer #{current_layer_index}: #{ex.message}" }
            return
          end
        end
      ensure
        source.shift(processed_count) if processed_count > 0
      end

      save_memories_to_json

      # After processing all source items from ingest_pending, check if Layer 0 needs consolidation
      # Only do this for layer -1 (ingest_pending), not for actual layers (to avoid chain reactions)
      if current_layer_index == -1 && current_num_tokens(target_layer_index) >= @layer_token_capacity
        cascade(target_layer_index)
      end
    end

    private def calculate_tokens(msgs : Enumerable(String)) : Int32
      msgs.sum { |msg| msg.size // 4 }
    end

    private def calculate_chunk_size_to_reach_target(msgs : Array(String), target_tokens : Int32) : Int32
      total_tokens = calculate_tokens(msgs)
      return 0 if total_tokens <= target_tokens

      tokens_to_remove = total_tokens - target_tokens
      removed_tokens = 0
      chunk_size = 0

      msgs.each do |msg|
        removed_tokens += msg.size // 4
        chunk_size += 1
        break if removed_tokens >= tokens_to_remove
      end

      chunk_size
    end

    # Data transfer object

    private struct FileData
      include JSON::Serializable

      property ingest_pending : Array(String)
      property layers : Array(Array(String))

      def initialize(
        @ingest_pending, # queue of context messages waiting for layer 0
        @layers,
      )
      end
    end

    private def load_memories_from_json : Nil
      begin
        data = FileData.from_json(File.read(@memory_file))
        @ingest_pending = data.ingest_pending
        @layers = data.layers
      rescue e : File::NotFoundError
        save_memories_to_json
      end
    end

    private def save_memories_to_json : Nil
      data = FileData.new(@ingest_pending, @layers)
      File.write(@memory_file, data.to_json)
    end

    private def strip_thinking(msg : String) : String
      # Remove <think>...</think> blocks and their contents
      # Uses regex with multiline flag to handle thinking blocks that span multiple lines
      msg.gsub(/<think>.*?<\/think>/m, "")
    end
  end
end
