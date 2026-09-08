# mantle/session.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./storage/context_manager"
require "./steps/step"
require "./clients/receipt_writer"
require "./support/log_context"
require "digest/sha256"
require "uuid"

module Mantle
  # High-level turn orchestrator and queue consumer.
  #
  # Coordinates message ingestion, idempotency guarantees, canonical context graph commits,
  # ephemeral injection view projection, and deterministic audit receipts via ReceiptWriter.
  #
  # Concurrency: `Mantle::Session` instances are designed for single-caller usage per session.
  # Daemon architectures or multi-session agents isolate concurrent workers by provisioning
  # independent `Session` instances per conversation / session ID.
  class Session
    # Queue item for channel-based consumer execution.
    record QueueItem,
      trigger : String | Mantle::Message,
      system_injections : Array(Mantle::Message) = [] of Mantle::Message,
      pre_history_injections : Array(Mantle::Message) = [] of Mantle::Message,
      tail_injections : Array(Mantle::Message) = [] of Mantle::Message,
      max_retries : Int32 = 3,
      retry_count : Int32 = 0

    # The context manager orchestrating canonical and memory stores.
    property context_manager : Mantle::Storage::ContextManager

    # The graph-isolated execution transform.
    property step : Mantle::Step

    # Optional file path for appending structured JSONL audit receipts.
    property log_file : String?

    # Model name identifier recorded in audit receipts.
    property model_name : String

    # Size threshold before triggering logrotate warning on the receipt file.
    property size_warning_threshold_bytes : Int64

    # Creates a new Session orchestrator.
    def initialize(
      @context_manager : Mantle::Storage::ContextManager,
      @step : Mantle::Step,
      @log_file : String? = nil,
      @model_name : String = "mantle-session",
      @size_warning_threshold_bytes : Int64 = 52_428_800_i64,
    )
    end

    # Appends a trigger message directly to the canonical context graph, returning self.
    def <<(trigger : String | Mantle::Message) : self
      @context_manager << trigger
      self
    end

    # Executes a single turn against the session pipeline with streaming chunk support.
    #
    # 1. Idempotently records the trigger message to the context graph.
    # 2. Projects the view with spatial ephemeral injections.
    # 3. Invokes the graph-isolated `Step#run`.
    # 4. On success: commits the assistant response to the canonical graph and emits a receipt.
    # 5. On failure: leaves the context uncorrupted and emits an error receipt.
    def run_turn(
      trigger : String | Mantle::Message,
      system_injections : Array(Mantle::Message) = [] of Mantle::Message,
      pre_history_injections : Array(Mantle::Message) = [] of Mantle::Message,
      tail_injections : Array(Mantle::Message) = [] of Mantle::Message,
      is_retry : Bool = false,
      &stream_block : String -> Nil
    ) : Mantle::StepResult(String, Mantle::StepError)
      start_time = Time.instant
      timestamp = Time.utc.to_s("%Y-%m-%dT%H:%M:%S.%3NZ")
      sequence_id = Mantle::LogContext.sequence_id || UUID.random.to_s

      # 1. Ingest & commit trigger unless this is an idempotent retry
      unless is_retry || trigger_already_recorded?(trigger)
        @context_manager << trigger
      end

      # 2. Project view with spatial ephemeral injections
      projected_view = @context_manager.project_view(
        system_injections: system_injections,
        pre_history_injections: pre_history_injections,
        tail_injections: tail_injections
      )

      # 3. Execute graph-isolated step transform
      result = @step.run(projected_view, &stream_block)
      latency_ms = (Time.instant - start_time).total_milliseconds.to_i

      # 4. Package ephemeral injection state for audit logging
      injections_audit = Mantle::Clients::EphemeralInjections.new(
        system: system_injections,
        pre_history: pre_history_injections,
        tail: tail_injections,
        memory_view: @context_manager.memory_store.current_view
      )

      # 5. Handle outcome
      if result.ok?
        if reply = result.value
          @context_manager.add_assistant_message(
            reply,
            tool_calls: result.raw_response.try(&.tool_calls)
          )
        end

        emit_receipt(
          sequence_id: sequence_id,
          timestamp: timestamp,
          prompt: projected_view,
          injections: injections_audit,
          response: result.raw_response,
          latency_ms: latency_ms,
          status: "success",
          error_message: nil
        )
      else
        emit_receipt(
          sequence_id: sequence_id,
          timestamp: timestamp,
          prompt: projected_view,
          injections: injections_audit,
          response: result.raw_response,
          latency_ms: latency_ms,
          status: "error",
          error_message: result.error.to_s
        )
      end

      result
    end

    # Executes a single turn synchronously without a streaming chunk block.
    def run_turn(
      trigger : String | Mantle::Message,
      system_injections : Array(Mantle::Message) = [] of Mantle::Message,
      pre_history_injections : Array(Mantle::Message) = [] of Mantle::Message,
      tail_injections : Array(Mantle::Message) = [] of Mantle::Message,
      is_retry : Bool = false,
    ) : Mantle::StepResult(String, Mantle::StepError)
      run_turn(
        trigger: trigger,
        system_injections: system_injections,
        pre_history_injections: pre_history_injections,
        tail_injections: tail_injections,
        is_retry: is_retry
      ) { |_| }
    end

    # Convenience overload accepting string injections.
    def run_turn(
      trigger : String | Mantle::Message,
      system_injections : Array(String) = [] of String,
      pre_history_injections : Array(String) = [] of String,
      tail_injections : Array(String) = [] of String,
      is_retry : Bool = false,
      &stream_block : String -> Nil
    ) : Mantle::StepResult(String, Mantle::StepError)
      run_turn(
        trigger: trigger,
        system_injections: system_injections.map { |s| Mantle::Message.new("system", s) },
        pre_history_injections: pre_history_injections.map { |s| Mantle::Message.new("system", s) },
        tail_injections: tail_injections.map { |s| Mantle::Message.new("system", s) },
        is_retry: is_retry,
        &stream_block
      )
    end

    # Convenience overload accepting string injections without a chunk block.
    def run_turn(
      trigger : String | Mantle::Message,
      system_injections : Array(String) = [] of String,
      pre_history_injections : Array(String) = [] of String,
      tail_injections : Array(String) = [] of String,
      is_retry : Bool = false,
    ) : Mantle::StepResult(String, Mantle::StepError)
      run_turn(
        trigger: trigger,
        system_injections: system_injections,
        pre_history_injections: pre_history_injections,
        tail_injections: tail_injections,
        is_retry: is_retry
      ) { |_| }
    end

    # Consumes messages from an incoming channel with backoff retries for Retryable errors
    # and routing to a dead-letter channel for Terminal errors.
    def consume_queue(
      inbox : Channel(QueueItem),
      outbox : Channel(Mantle::StepResult(String, Mantle::StepError))? = nil,
      stream_channel : Channel(String)? = nil,
      dead_letter : Channel(Tuple(QueueItem, Mantle::StepError))? = nil,
      backoff_ms : Int32 = 50,
    )
      while item = inbox.receive?
        result = run_turn(
          trigger: item.trigger,
          system_injections: item.system_injections,
          pre_history_injections: item.pre_history_injections,
          tail_injections: item.tail_injections,
          is_retry: item.retry_count > 0
        ) do |chunk|
          stream_channel.try &.send(chunk)
        end

        if result.ok?
          outbox.try &.send(result)
        else
          if (err = result.error) && err.retryable? && (item.retry_count < item.max_retries)
            sleep (backoff_ms * (2 ** item.retry_count)).milliseconds
            next_item = QueueItem.new(
              trigger: item.trigger,
              system_injections: item.system_injections,
              pre_history_injections: item.pre_history_injections,
              tail_injections: item.tail_injections,
              max_retries: item.max_retries,
              retry_count: item.retry_count + 1
            )
            spawn { inbox.send(next_item) }
          else
            dead_letter.try &.send({item, result.error || Mantle::StepError::ClientFailure})
            outbox.try &.send(result)
          end
        end
      end
    end

    private def trigger_already_recorded?(trigger : String | Mantle::Message) : Bool
      expected_content = trigger.is_a?(Mantle::Message) ? (trigger.content || "") : trigger
      expected_role = trigger.is_a?(Mantle::Message) ? trigger.role.downcase : "user"

      # Check the last message in the context store
      last_msg = @context_manager.context_store.current_view.last?
      return false unless last_msg

      last_msg.role.downcase == expected_role && (last_msg.content || "") == expected_content
    end

    private def emit_receipt(
      sequence_id : String,
      timestamp : String,
      prompt : Array(Mantle::Message),
      injections : Mantle::Clients::EphemeralInjections,
      response : Mantle::Clients::Response?,
      latency_ms : Int32,
      status : String,
      error_message : String?,
    )
      log_path = @log_file
      return unless log_path

      input_hash = Digest::SHA256.hexdigest(prompt.to_json)

      entry = {
        "id"                   => UUID.random.to_s,
        "sequence_id"          => sequence_id,
        "timestamp"            => timestamp,
        "model"                => @model_name,
        "input_hash"           => input_hash,
        "prompt"               => prompt,
        "ephemeral_injections" => injections,
        "raw_output"           => {
          "content"           => response ? response.content : nil,
          "thinking"          => response ? response.thinking : nil,
          "tool_calls"        => response ? response.tool_calls : nil,
          "done_reason"       => response ? response.done_reason : nil,
          "prompt_eval_count" => response ? response.prompt_eval_count : nil,
          "eval_count"        => response ? response.eval_count : nil,
        },
        "latency_ms"    => latency_ms,
        "status"        => status,
        "error_message" => error_message,
      }

      Mantle::Clients::ReceiptWriter.enqueue(
        Mantle::Clients::ReceiptWriter::Task.new(
          log_file: log_path,
          entry_json: entry.to_json,
          size_threshold: @size_warning_threshold_bytes,
          ephemeral_injections: injections
        )
      )
    end
  end
end
