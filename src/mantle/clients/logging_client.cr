# mantle/clients/logging_client.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./client"
require "../support/log_context"
require "digest/sha256"
require "json"
require "time"
require "uuid"

module Mantle::Clients
  # Decorator client that wraps an underlying client of type *T* to automatically log
  # every LLM call transaction as a structured JSONL receipt.
  class LoggingClient(T) < Client
    # Class-level mutex to ensure thread-safe/fiber-safe appending to log files
    @@file_mutex = Mutex.new

    # Represents the wrapped underlying client.
    property client : T

    # Represents the path to the JSONL log file.
    property log_file : String

    # Threshold size in bytes (default 50MB) before triggering a logrotate warning.
    property size_warning_threshold_bytes : Int64

    # Flag tracking whether warning has been emitted for current file size state
    @warned_file_size : Bool = false

    # Creates a new `LoggingClient` decorating *client* and writing receipts to *log_file*.
    def initialize(
      @client : T,
      @log_file : String,
      @size_warning_threshold_bytes : Int64 = 52_428_800_i64
    )
    end

    # Executes the LLM request while logging execution metrics, prompt, and response to JSONL.
    def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Response
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
          response: nil,
          latency_ms: latency,
          status: "error",
          error_message: ex.message
        )

        raise ex
      end
    end

    # Returns the temperature setting from the wrapped client.
    def temperature : Float64
      @client.temperature
    end

    # Sets the temperature setting on the wrapped client.
    def temperature=(value : Float64)
      @client.temperature = value
    end

    # Delegate all unhandled methods (such as `max_tokens`, `api_url`, etc.) to `@client`.
    forward_missing_to @client

    private def log_receipt(
      sequence_id : String,
      timestamp : String,
      model : String,
      input_hash : String,
      prompt : Array(Mantle::Message),
      response : Response?,
      latency_ms : Int32,
      status : String,
      error_message : String?
    )
      entry = {
        "id"            => UUID.random.to_s,
        "sequence_id"   => sequence_id,
        "timestamp"     => timestamp,
        "model"         => model,
        "input_hash"     => input_hash,
        "prompt"        => prompt,
        "raw_output"    => {
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

      @@file_mutex.synchronize do
        begin
          dir = File.dirname(@log_file)
          Dir.mkdir_p(dir) unless Dir.exists?(dir)

          File.open(@log_file, "a") do |f|
            entry.to_json(f)
            f.puts
          end

          check_file_size_warning
        rescue write_ex
          Mantle::Log.error { "LoggingClient failed to write JSONL receipt to #{@log_file}: #{write_ex.message}" }
        end
      end
    end

    private def check_file_size_warning
      if File.exists?(@log_file)
        size = File.size(@log_file)
        if size > @size_warning_threshold_bytes
          unless @warned_file_size
            @warned_file_size = true
            size_mb = (size.to_f / 1_048_576.0).round(2)
            Mantle::Log.warn { "Warning: JSONL log file '#{@log_file}' size (#{size_mb} MB) exceeds threshold. Please configure logrotate." }
          end
        else
          @warned_file_size = false
        end
      end
    rescue
      # Ignore size check error
    end
  end
end
