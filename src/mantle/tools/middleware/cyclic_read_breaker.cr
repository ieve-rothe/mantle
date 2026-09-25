# mantle/tools/middleware/cyclic_read_breaker.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "json"
require "../middleware"
require "../tools"

module Mantle::Tools::Middleware
  # Circuit breaker middleware designed to halt degenerate, cyclic unmutated
  # inspection loops (e.g. read_file(A) -> read_file(B) -> read_file(A))
  # without penalizing iterative edit-compile-test loops.
  class CyclicReadBreaker < Base
    DEFAULT_INSPECTION_TOOLS = Set{
      "read_file",
      "list_directory",
      "list_files",
      "search_files",
      "search",
      "file_info",
    }

    DEFAULT_MUTATION_TOOLS = Set{
      "write_file",
      "replace_in_file",
      "append_to_file",
      "create_file",
      "delete_file",
    }

    DEFAULT_THRESHOLD = 3

    property inspection_tools : Set(String)
    property mutation_tools : Set(String)
    property threshold : Int32
    property window_size : Int32?
    property? raise_on_trip : Bool

    getter inspection_history : Hash(Tuple(String, String), Int32)
    getter? tripped : Bool = false
    getter last_refusal : String? = nil
    getter tripped_tool : String? = nil
    getter tripped_args : String? = nil

    @call_log : Deque(Tuple(String, String))

    def initialize(
      @threshold : Int32 = DEFAULT_THRESHOLD,
      @inspection_tools : Set(String) = DEFAULT_INSPECTION_TOOLS.dup,
      @mutation_tools : Set(String) = DEFAULT_MUTATION_TOOLS.dup,
      @window_size : Int32? = nil,
      @raise_on_trip : Bool = false,
    )
      @inspection_history = Hash(Tuple(String, String), Int32).new(0)
      @call_log = Deque(Tuple(String, String)).new
    end

    # Resets consecutive tracking and inspection counts when a workspace mutation occurs.
    def record_mutation : Nil
      @inspection_history.clear
      @call_log.clear
      @tripped = false
      @last_refusal = nil
      @tripped_tool = nil
      @tripped_args = nil
    end

    # Complete reset of the breaker state.
    def reset : Nil
      record_mutation
    end

    def call(
      tool_name : String,
      args : Hash(String, JSON::Any),
      next_handler : Proc(Hash(String, JSON::Any), String),
    ) : String
      # 1. Workspace mutation tools reset the breaker
      if @mutation_tools.includes?(tool_name)
        result = next_handler.call(args)
        record_mutation unless result.includes?("\"error\":")
        return result
      end

      # 2. Non-inspection tools (e.g., shell commands, diagnostics) pass through unconstrained
      unless @inspection_tools.includes?(tool_name)
        return next_handler.call(args)
      end

      # 3. Track inspection call repetitions
      args_json = args.to_json
      key = {tool_name, args_json}

      current_count = @inspection_history[key] + 1
      @inspection_history[key] = current_count

      if window = @window_size
        @call_log << key
        if @call_log.size > window
          evicted_key = @call_log.shift
          if @inspection_history.has_key?(evicted_key)
            @inspection_history[evicted_key] -= 1
            if @inspection_history[evicted_key] <= 0
              @inspection_history.delete(evicted_key)
            end
          end
        end
      end

      # 4. Check if threshold reached
      if current_count >= @threshold
        @tripped = true
        @tripped_tool = tool_name
        @tripped_args = args_json
        refusal = "ERR_CYCLIC_READ: Inspection tool '#{tool_name}' called #{current_count} times with identical arguments without any intervening workspace mutation. Contents were previously provided. Cease re-reading and take concrete action or write a plan."
        @last_refusal = refusal

        if @raise_on_trip
          raise Mantle::Tools::TerminalToolError.new(refusal)
        else
          return {
            error:   refusal,
            refused: true,
          }.to_json
        end
      end

      next_handler.call(args)
    end
  end
end
