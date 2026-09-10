# mantle/clients/logging_client.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./client"
require "./receipt_writer"
require "../support/log_context"
require "digest/sha256"
require "json"
require "time"
require "uuid"

module Mantle::Clients
  # Decorator client that wraps an underlying client of type *T* to automatically log
  # every LLM call transaction as a structured JSONL receipt with spatial ephemeral injection auditing.
  class LoggingClient(T) < Client
    # Represents the wrapped underlying client.
    property client : T

    # Represents the path to the JSONL log file.
    property log_file : String

    # Threshold size in bytes (default 50MB) before triggering a logrotate warning.
    property size_warning_threshold_bytes : Int64

    # Creates a new `LoggingClient` decorating *client* and writing receipts to *log_file*.
    def initialize(
      @client : T,
      @log_file : String,
      @size_warning_threshold_bytes : Int64 = 52_428_800_i64,
    )
    end

    # Executes the LLM request while logging execution metrics, prompt, and response to JSONL.
    def execute(
      messages : Array(Mantle::Message),
      tools : Array(Mantle::Tools::Tool)? = nil,
      ephemeral_injections : EphemeralInjections? = nil,
      &on_chunk : String -> Nil
    ) : Response
      start_time = Time.instant
      timestamp = Time.utc.to_s("%Y-%m-%dT%H:%M:%S.%3NZ")

      input_hash = Digest::SHA256.hexdigest(messages.to_json)
      model_name = @client.responds_to?(:model_name) ? @client.model_name.to_s : "unknown"
      sequence_id = Mantle::LogContext.sequence_id || UUID.random.to_s

      begin
        response = @client.execute(messages, tools, &on_chunk)
        latency = (Time.instant - start_time).total_milliseconds.to_i

        log_receipt(
          sequence_id: sequence_id,
          timestamp: timestamp,
          model: model_name,
          input_hash: input_hash,
          prompt: messages,
          ephemeral_injections: ephemeral_injections,
          response: response,
          latency_ms: latency,
          status: "success",
          error_message: nil
        )

        response
      rescue ex
        latency = (Time.instant - start_time).total_milliseconds.to_i

        log_receipt(
          sequence_id: sequence_id,
          timestamp: timestamp,
          model: model_name,
          input_hash: input_hash,
          prompt: messages,
          ephemeral_injections: ephemeral_injections,
          response: nil,
          latency_ms: latency,
          status: "error",
          error_message: ex.message
        )

        raise ex
      end
    end

    # Non-streaming execution overload.
    def execute(
      messages : Array(Mantle::Message),
      tools : Array(Mantle::Tools::Tool)? = nil,
      ephemeral_injections : EphemeralInjections? = nil,
    ) : Response
      execute(messages, tools, ephemeral_injections) { |_| }
    end

    # Returns the temperature setting from the wrapped client.
    def temperature : Float64
      @client.temperature
    end

    # Sets the temperature setting on the wrapped client.
    def temperature=(value : Float64)
      @client.temperature = value
    end

    # Flushes all pending receipt log writes to disk.
    def flush
      ReceiptWriter.flush
    end

    # Flushes all pending receipt log writes to disk across all client specializations.
    def self.flush
      ReceiptWriter.flush
    end

    # Delegate all unhandled methods (such as `max_tokens`, `api_url`, etc.) to `@client`.
    forward_missing_to @client

    private def log_receipt(
      sequence_id : String,
      timestamp : String,
      model : String,
      input_hash : String,
      prompt : Array(Mantle::Message),
      ephemeral_injections : EphemeralInjections?,
      response : Response?,
      latency_ms : Int32,
      status : String,
      error_message : String?,
    )
      entry = {
        "id"                   => UUID.random.to_s,
        "sequence_id"          => sequence_id,
        "timestamp"            => timestamp,
        "model"                => model,
        "input_hash"           => input_hash,
        "prompt"               => prompt,
        "ephemeral_injections" => ephemeral_injections,
        "raw_output"           => {
          "content"           => response ? response.content : nil,
          "thinking"          => response ? response.thinking : nil,
          "tool_calls"        => response ? response.tool_calls : nil,
          "done_reason"       => response ? response.done_reason : nil,
          "prompt_eval_count" => response ? response.prompt_eval_count : nil,
          "eval_count"        => response ? response.eval_count : nil,
        },
        "raw_request"          => parse_raw_json(response.try(&.raw_request)),
        "raw_response"         => parse_raw_response(response.try(&.raw_response)),
        "latency_ms"           => latency_ms,
        "status"               => status,
        "error_message"        => error_message,
      }

      ReceiptWriter.enqueue(
        ReceiptWriter::Task.new(
          log_file: @log_file,
          entry_json: entry.to_json,
          size_threshold: @size_warning_threshold_bytes,
          ephemeral_injections: ephemeral_injections
        )
      )
    end

    private def parse_raw_json(str : String?) : JSON::Any?
      return nil unless str
      begin
        JSON.parse(str)
      rescue
        JSON::Any.new(str)
      end
    end

    private def parse_raw_response(str : String?) : JSON::Any?
      return nil unless str
      begin
        JSON.parse(str)
      rescue
        begin
          chunks = str.lines.reject(&.strip.empty?).map { |line| JSON.parse(line) }
          chunks.empty? ? JSON::Any.new(str) : JSON::Any.new(chunks)
        rescue
          JSON::Any.new(str)
        end
      end
    end
  end
end
