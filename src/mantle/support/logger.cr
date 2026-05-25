# mantle/logger.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "file"
require "time"
require "./app_logger"

module Mantle::Support
  # Represents an abstract base logger defining the logging contract for Mantle.
  #
  # Abstract class implemented to allow a 'DummyLogger' or other custom loggers to be used.
  abstract class Logger
    # Represents the display name for user messages.
    property user_name : String

    # Represents the display name for bot messages.
    property bot_name : String

    # Represents whether the logger should include the model's thinking/reasoning process.
    property include_thinking : Bool

    # Creates a logger with the specified *user_name*, *bot_name*, and optional *include_thinking* flag.
    def initialize(@user_name : String, @bot_name : String, @include_thinking : Bool = false)
    end

    # Logs a *message* labeled with *label*.
    #
    # The *label* is a category label (e.g., `"Context Input"`, `"Model Response"`, or `"ERROR"`).
    abstract def log(label : String, message : String)

    # Logs a user or bot message with the given *role* (e.g., `:user` or `:bot`), *message*, *context*, and optional *thinking*.
    #
    # This is the main method for logging interactions in flows.
    abstract def log_message(role : Symbol, message : String, context : String, thinking : String? = nil)

    # Formats *message* and optional *thinking* tags together if thinking process is included.
    protected def format_with_thinking(message : String, thinking : String?) : String
      if @include_thinking && thinking && !thinking.empty?
        "🤔 [Thinking Process]\n#{thinking}\n\n[Response]\n#{message}"
      else
        message
      end
    end

    # Logs raw API *request* and *response* payloads.
    abstract def log_api_payloads(request : String, response : String)
  end

  # Represents a concrete logger that writes formatted messages to a log file.
  #
  # Formats messages with a timestamp and appends them to a file.
  class FileLogger < Logger
    # Represents the path to the log file on disk.
    property log_file : String

    # Creates a new `FileLogger` targeting *log_file* with the specified *user_name*, *bot_name*, and optional *include_thinking*.
    def initialize(@log_file : String, user_name : String, bot_name : String, include_thinking : Bool = false)
      super(user_name, bot_name, include_thinking)
      new_context
    end

    # Writes a formatted *message* labeled with *label* to the log file.
    #
    # Rescues and prints error to `Mantle::Log` if the file write fails.
    def log(label : String, message : String)
      formatted_entry = format(message, label)
      File.write(@log_file, formatted_entry, mode: "a")
    rescue ex
      Mantle::Support::Log.error { "Logger failed to write: #{ex.message}" }
    end

    # Logs a user or bot message targeting *role* with *message*, *context*, and optional *thinking*.
    def log_message(role : Symbol, message : String, context : String, thinking : String? = nil)
      name = role == :user ? @user_name : @bot_name
      final_message = format_with_thinking(message, thinking)
      log(name, final_message)
    end

    # Logs raw API *request* and *response* payloads (no-op in `FileLogger`).
    def log_api_payloads(request : String, response : String)
      # No-op
    end

    # Clears the contents of the log file.
    def clear_log_file
      File.write(@log_file, "", mode: "w")
    end

    # :nodoc:
    private def new_context
      separator = "\n" + get_ascii_divider(:stars) + "\n"
      File.write(@log_file, separator, mode: "a")
    end

    # :nodoc:
    private def format(message : String, label : String)
      "[#{Time.utc.to_s("%F")}] -- [#{label}] #{message}\n" + log_separator + "\n"
    end

    # :nodoc:
    private def log_separator
      "#{"-" * 50}"
    end

    # :nodoc:
    private def get_ascii_divider(divider_type : Symbol = :random) : String
      dividers = {
        cat:     "=^..^=   =^..^=   =^..^=   =^..^=   =^..^=   =^..^=   =^..^=",
        stars:   "★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★",
        hearts:  "♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥",
        flowers: "✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀",
        bubbles: "°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°",
      }

      if divider_type == :random
        divider_keys = dividers.keys
        random_key = divider_keys.sample
        return dividers[random_key]
      elsif dividers.has_key?(divider_type)
        return dividers[divider_type]
      else
        return dividers[:stars]
      end
    end
  end

  # Represents a logger that writes interaction details across multiple dedicated files.
  class DetailedLogger < FileLogger
    # Represents the path to the context log file.
    property context_log_file : String

    # Represents the path to the last user message file.
    property last_user_message_file : String

    # Represents the path to the last bot message file.
    property last_bot_message_file : String

    # Represents the optional path to the last API request payload file.
    property last_request_file : String?

    # Represents the optional path to the last API response payload file.
    property last_response_file : String?

    # Creates a new `DetailedLogger` with the specified output file paths and configuration.
    def initialize(@log_file : String, @context_log_file : String, @last_user_message_file : String, @last_bot_message_file : String, user_name : String, bot_name : String, @last_request_file : String? = nil, @last_response_file : String? = nil, include_thinking : Bool = false)
      super(@log_file, user_name, bot_name, include_thinking)
    end

    # Logs a *message* with full *context* and *thinking* process to the main log file and role-specific files.
    #
    # Overrides `FileLogger#log_message` to write details across:
    # - Main log file (via parent `FileLogger`)
    # - Context log file
    # - Role-specific message files (*last_user_message_file* or *last_bot_message_file*)
    def log_message(role : Symbol, message : String, context : String, thinking : String? = nil)
      # Log to main log file
      super(role, message, context, thinking)

      # Write current context
      File.write(@context_log_file, context, mode: "w")

      # Prepare message with thinking if requested
      final_message = format_with_thinking(message, thinking)

      # Write to role-specific file
      case role
      when :user
        File.write(@last_user_message_file, final_message, mode: "w")
      when :bot
        File.write(@last_bot_message_file, final_message, mode: "w")
      end
    rescue ex
      Mantle::Support::Log.error { "DetailedLogger failed to write: #{ex.message}" }
    end

    # Logs the raw API *request* and *response* payloads to their respective files.
    def log_api_payloads(request : String, response : String)
      File.write(@last_request_file.not_nil!, request, mode: "w") if @last_request_file
      File.write(@last_response_file.not_nil!, response, mode: "w") if @last_response_file
    rescue ex
      Mantle::Support::Log.error { "DetailedLogger failed to write payloads: #{ex.message}" }
    end
  end
end
