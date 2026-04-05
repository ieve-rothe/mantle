# mantle/memory_store.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Manages memory for the agent.

require "json"

module Mantle
  # Maybe write a base class once we have an implementation for Layered and then are going to add another type of memorystore

  class JSONLayeredMemoryStore
    property memory_file : String
    property layer_target : Int32
    property layer_capacity : Int32
    property squishifier : Proc(Array(String), String)

    property ingest_pending : Array(String) = [] of String
    property layers : Array(Array(String)) = [] of Array(String)

    property ingest_step_size : Int32

    def initialize(@memory_file,
                   @layer_capacity,
                   @layer_target,
                   @squishifier)
      if layer_target >= layer_capacity
        raise Exception.new("layer_capacity must be greater than layer_target")
      elsif layer_target <= 0
        raise Exception.new("layer_target must be positive")
      end
      @ingest_step_size = (layer_capacity - layer_target)
      load_memories_from_json
    end

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

    def ingest(messages : Array(String)) : Nil
      @ingest_pending.concat(messages)
      save_memories_to_json

      cascade(-1) # layer -1 indicates input to layer 0, ie incoming context
      # Push messages received into ingest_pending
      # Check how many chunks (N) of ingest_step_size we have in ingest_pending. (Ideally ingest_pending would be empty when we start, and then we just fill it up with the messages coming out of context right now, but our fault tolerance for inability to get squishification from the model means there could be messages from last time that never got squishified into memory.)
      # Check that target layer has space. If we're at layer_capacity, call ingest for the target layer to clear up space. (Which runs this same function, so might need to do some squishification deeper in the recursion stack)
      # Then, run squishifier N times. If there are fewer than ingest_step_size in the last chunk, just squish it anyway? Or maybe we'll save it for next time.
      # For each result of squishifier, stick it in Layer 0.
      # If we can't get a response from the model, don't pop anytihng out of ingest_pending, just leave it there and log / puts an error.
    end

    # Private -------------------------------------------------------------

    private def cascade(current_layer_index : Int32) : Nil
      # Prevent infinite recursion - reasonable max layer depth
      if current_layer_index > 50
        puts "[System] Maximum layer depth (50) reached"
        return
      end

      chunks = [] of Array(String)
      target_layer_index = current_layer_index + 1

      if current_layer_index == -1
        source = @ingest_pending
      else
        source = @layers[current_layer_index]
      end

      if @layers.size <= target_layer_index
        @layers << [] of String
      end

      # For layer -1 (ingest_pending), process all messages immediately
      # For actual layers, batch by ingest_step_size
      chunk_size = current_layer_index == -1 ? source.size : @ingest_step_size

      while source.size >= chunk_size && chunk_size > 0
        # Before adding, check if target layer is already at capacity
        # If so, consolidate it first to make room
        while @layers[target_layer_index].size >= @layer_capacity
          cascade(target_layer_index)
          # If consolidation didn't free up space, we can't proceed
          break if @layers[target_layer_index].size >= @layer_capacity
        end

        # If target is still at capacity after consolidation, we can't add more
        if @layers[target_layer_index].size >= @layer_capacity
          puts "[System] Layer #{target_layer_index} still at capacity after consolidation"
          return
        end

        chunk = source.first(chunk_size)

        begin
          summary = @squishifier.call(chunk)
          # Strip thinking tags from the squishified summary
          summary = strip_thinking(summary)
          # If no exception from squishifier, then successful response from LLM
          source.shift(chunk_size) # Remove messages that we squished
          timestamp = Time.utc.to_s("%Y-%m-%d %H:%M")
          @layers[target_layer_index] << "[#{timestamp}] #{summary}"

          # Recalculate chunk_size for next iteration (only matters for layer -1)
          chunk_size = current_layer_index == -1 ? source.size : @ingest_step_size
        rescue ex
          puts "[System] Squishifier failed at layer #{current_layer_index}: #{ex.message}"
          return
        end
      end

      save_memories_to_json

      # After processing all source items from ingest_pending, check if Layer 0 needs consolidation
      # (This handles the case where we filled it to capacity but have no more items to add)
      # Only do this for layer -1 (ingest_pending), not for actual layers (to avoid chain reactions)
      if current_layer_index == -1 && @layers[target_layer_index].size >= @layer_capacity
        cascade(target_layer_index)
      end
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
