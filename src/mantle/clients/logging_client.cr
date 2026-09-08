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
  # Background asynchronous writer that receives JSONL log receipts over a buffered Channel
  # and writes them to disk using a single shared Mutex across all client specializations.
  module ReceiptWriter
    # Shared Mutex ensuring file writes are thread/fiber safe across all client specializations
    class_getter file_mutex : Mutex = Mutex.new

    # Record defining a receipt write task or a synchronization flush task
    record Task,
      log_file : String,
      entry_json : String,
      size_threshold : Int64,
      sync_channel : Channel(Nil)? = nil

    # Buffered channel for asynchronous receipt logging
    class_getter channel : Channel(Task) = Channel(Task).new(1024)

    # Worker state
    @@worker_started : Bool = false
    @@worker_mutex : Mutex = Mutex.new

    # Track warned files across log destinations
    @@warned_files = Set(String).new
    @@warned_mutex = Mutex.new

    # Ensures the background writer fiber is running
    def self.ensure_worker_running
      return if @@worker_started
      @@worker_mutex.synchronize do
        return if @@worker_started
        @@worker_started = true
        spawn(name: "mantle-receipt-logger") do
          loop do
            task = channel.receive
            process_task(task)
          end
        end
      end
    end

    # Enqueues a receipt for asynchronous writing and yields briefly to allow the worker fiber to run
    def self.enqueue(task : Task)
      ensure_worker_running
      channel.send(task)
      Fiber.yield
    end

    # Blocks execution until all tasks currently queued in the channel have been processed and written to disk.
    def self.flush
      ensure_worker_running
      sync_ch = Channel(Nil).new
      channel.send(Task.new(log_file: "", entry_json: "", size_threshold: 0_i64, sync_channel: sync_ch))
      sync_ch.receive
    end

    private def self.process_task(task : Task)
      unless task.entry_json.empty?
        file_mutex.synchronize do
          begin
            dir = File.dirname(task.log_file)
            Dir.mkdir_p(dir) unless Dir.exists?(dir)

            File.open(task.log_file, "a") do |f|
              f.puts(task.entry_json)
              f.flush
            end

            check_file_size_warning(task.log_file, task.size_threshold)
          rescue write_ex
            Mantle::Log.error { "LoggingClient failed to write JSONL receipt to #{task.log_file}: #{write_ex.message}" }
          end
        end
      end

      if sync = task.sync_channel
        sync.send(nil)
      end
    end

    private def self.check_file_size_warning(log_file : String, threshold : Int64)
      if File.exists?(log_file)
        size = File.size(log_file)
        if size > threshold
          should_warn = false
          @@warned_mutex.synchronize do
            unless @@warned_files.includes?(log_file)
              @@warned_files << log_file
              should_warn = true
            end
          end
          if should_warn
            size_mb = (size.to_f / 1_048_576.0).round(2)
            Mantle::Log.warn { "Warning: JSONL log file '#{log_file}' size (#{size_mb} MB) exceeds threshold. Please configure logrotate." }
          end
        else
          @@warned_mutex.synchronize do
            @@warned_files.delete(log_file)
          end
        end
      end
    rescue
      # Ignore size check error
    end
  end

  # Decorator client that wraps an underlying client of type *T* to automatically log
  # every LLM call transaction as a structured JSONL receipt.
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

      ReceiptWriter.enqueue(
        ReceiptWriter::Task.new(
          log_file: @log_file,
          entry_json: entry.to_json,
          size_threshold: @size_warning_threshold_bytes
        )
      )
    end
  end
end
