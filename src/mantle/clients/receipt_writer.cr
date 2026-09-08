# mantle/clients/receipt_writer.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "./message"
require "json"

module Mantle::Clients
  # Formalized container for ephemeral prompt injections and active memory state.
  struct EphemeralInjections
    include JSON::Serializable

    # System-level ephemeral injections (identity, runtime environment, base nudges).
    property system : Array(Mantle::Message)

    # Pre-history ephemeral injections (topic context, frame state, daemon flags).
    property pre_history : Array(Mantle::Message)

    # Tail ephemeral injections (formatting nudges, execution constraints, dev mode triggers).
    property tail : Array(Mantle::Message)

    # Serialized long-term memory view or summarization context active during the turn.
    @[JSON::Field(emit_null: false)]
    property memory_view : String?

    def initialize(
      @system : Array(Mantle::Message) = [] of Mantle::Message,
      @pre_history : Array(Mantle::Message) = [] of Mantle::Message,
      @tail : Array(Mantle::Message) = [] of Mantle::Message,
      @memory_view : String? = nil,
    )
    end

    def empty? : Bool
      @system.empty? && @pre_history.empty? && @tail.empty? && (@memory_view.nil? || @memory_view.not_nil!.empty?)
    end
  end

  # Dedicated background worker and synchronization primitive for writing structured JSONL receipts.
  module ReceiptWriter
    # Represents a pending receipt write task or synchronous barrier task.
    record Task,
      log_file : String,
      entry_json : String,
      size_threshold : Int64 = 52_428_800_i64,
      sync_channel : Channel(Nil)? = nil,
      ephemeral_injections : EphemeralInjections? = nil

    # Buffered channel for asynchronous receipt logging
    class_getter channel : Channel(Task) = Channel(Task).new(1024)

    @@worker_started = Atomic(Bool).new(false)
    @@warned_files = Set(String).new

    # Enqueues a receipt write task to the asynchronous background worker channel.
    def self.enqueue(task : Task)
      ensure_worker_running
      channel.send(task)
    end

    # Deterministically flushes all pending receipt tasks to disk, blocking until queue is cleared.
    def self.flush
      ensure_worker_running
      sync_ch = Channel(Nil).new
      channel.send(Task.new("", "", 0_i64, sync_channel: sync_ch))
      sync_ch.receive
    end

    private def self.ensure_worker_running
      return if @@worker_started.swap(true)

      spawn(name: "mantle-receipt-logger") do
        loop do
          task = channel.receive

          if !task.entry_json.empty?
            write_receipt(task)
          end

          task.sync_channel.try &.send(nil)
        end
      end
    end

    private def self.write_receipt(task : Task)
      dir = File.dirname(task.log_file)
      Dir.mkdir_p(dir) unless Dir.exists?(dir)

      File.open(task.log_file, "a") do |f|
        f.puts(task.entry_json)
        f.flush
      end

      check_size(task.log_file, task.size_threshold)
    rescue ex
      Mantle::Log.error { "Failed writing receipt to #{task.log_file}: #{ex.message}" }
    end

    private def self.check_size(log_file : String, threshold : Int64)
      return unless File.exists?(log_file)
      size = File.size(log_file)

      if size > threshold
        if @@warned_files.add?(log_file)
          size_mb = (size.to_f / 1_048_576.0).round(2)
          Mantle::Log.warn { "JSONL log '#{log_file}' (#{size_mb} MB) exceeds threshold. Configure logrotate." }
        end
      else
        @@warned_files.delete(log_file)
      end
    rescue
      # Ignore stat errors
    end
  end

  alias ReceiptTask = ReceiptWriter::Task
end

module Mantle
  alias EphemeralInjections = Mantle::Clients::EphemeralInjections
  alias ReceiptTask = Mantle::Clients::ReceiptTask
end
