# mantle/logger.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "file"
require "time"
require "./app_logger"

module Mantle
  # Abstract class for loggers
  #
  # Defines contract that loggers must follow.
  # Abstract class was implemented to allow a 'DummyLogger' to be used for unit tests
  abstract class Logger
    property user_name : String
    property bot_name : String

    def initialize(@user_name : String, @bot_name : String)
    end

    # Logs a message with generic label
    #
    # - `label`: A category label, eg "Context Input", "Model Response", "ERROR"
    # - `message`: Content to be logged
    abstract def log(label : String, message : String)

    # Logs a user or bot message with full context
    #
    # This is the main method for logging interactions in flows.
    # - `role`: Either :user or :bot (name is determined by role and stored user_name/bot_name)
    # - `message`: The actual message content
    # - `context`: The full conversation context at this point
    abstract def log_message(role : Symbol, message : String, context : String)

    # Logs the raw API payload for request and response
    #
    # - `request`: The raw JSON string sent to the model
    # - `response`: The raw JSON string returned by the model
    abstract def log_api_payloads(request : String, response : String)
  end

  # Concrete logger to write formatted messages to log file
  #
  # Formats messages with a timestamp and writes to file.
  class FileLogger < Logger
    # Path to log file on disk
    property log_file : String

    # Creates a new FileLogger
    #
    # - `log_file`: Path to file where logs will be appended
    # - `user_name`: Display name for user messages
    # - `bot_name`: Display name for bot messages
    def initialize(@log_file : String, user_name : String, bot_name : String)
      super(user_name, bot_name)
      new_context
    end

    # Writes a formatted message to log file
    #
    # Rescues and prints error to STDOUT if file write fails
    #
    # - `label`: A category label, eg "Context Input", "Model Response", "ERROR"
    # - `message`: Content to be logged
    def log(label : String, message : String)
      formatted_entry = format(message, label)
      File.write(@log_file, formatted_entry, mode: "a")
    rescue ex
      Mantle::Log.error { "Logger failed to write: #{ex.message}" }
    end

    # Logs a user or bot message
    #
    # For basic FileLogger, just writes to the main log file.
    # - `role`: Either :user or :bot
    # - `message`: The actual message content
    # - `context`: The full conversation context (not used in basic logger)
    def log_message(role : Symbol, message : String, context : String)
      name = role == :user ? @user_name : @bot_name
      log(name, message)
    end

    # Default implementation for FileLogger does not log payloads
    def log_api_payloads(request : String, response : String)
      # No-op
    end

    # ---

    def clear_log_file
      File.write(@log_file, "", mode: "w")
    end

    private def new_context
      separator = "\n" + get_ascii_divider(:stars) + "\n"
      File.write(@log_file, separator, mode: "a")
    end

    # ---

    # Formats a log entry with a UTC timestamp and label.
    private def format(message : String, label : String)
      "[#{Time.utc.to_s("%F")}] -- [#{label}] #{message}\n" + log_separator + "\n"
    end

    # Helper to draw a separator line in output
    private def log_separator
      "#{"-" * 50}"
    end

    # ---

    # Returns ASCII art dividers for file output
    # Cycles through multiple divider styles
    private def get_ascii_divider(divider_type : Symbol = :random) : String
      dividers = {
        cat:     "=^..^=   =^..^=   =^..^=   =^..^=   =^..^=   =^..^=   =^..^=",
        stars:   "★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★★",
        hearts:  "♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥•*¨*•.¸¸♥",
        flowers: "✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀✿❀",
        bubbles: "°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°°o○●○o°",
      }

      if divider_type == :random
        # Pick a random divider
        divider_keys = dividers.keys
        random_key = divider_keys.sample
        return dividers[random_key]
      elsif dividers.has_key?(divider_type)
        return dividers[divider_type]
      else
        # Default to stars if invalid type provided
        return dividers[:stars]
      end
    end
    # ---
  end

  class DetailedLogger < FileLogger
    property context_log_file : String
    property last_user_message_file : String
    property last_bot_message_file : String
    property last_request_file : String?
    property last_response_file : String?

    def initialize(@log_file : String, @context_log_file : String, @last_user_message_file : String, @last_bot_message_file : String, user_name : String, bot_name : String, @last_request_file : String? = nil, @last_response_file : String? = nil)
      super(@log_file, user_name, bot_name)
    end

    # Logs a user or bot message with full context
    #
    # Overrides FileLogger to write to multiple files:
    # - Main log file (via parent)
    # - Context file (always updated with current context)
    # - User or bot specific message file
    def log_message(role : Symbol, message : String, context : String)
      # Log to main log file
      super(role, message, context)

      # Write current context
      File.write(@context_log_file, context, mode: "w")

      # Write to role-specific file
      case role
      when :user
        File.write(@last_user_message_file, message, mode: "w")
      when :bot
        File.write(@last_bot_message_file, message, mode: "w")
      end
    rescue ex
      Mantle::Log.error { "DetailedLogger failed to write: #{ex.message}" }
    end

    # Logs the raw API payload for request and response to specific files
    def log_api_payloads(request : String, response : String)
      File.write(@last_request_file.not_nil!, request, mode: "w") if @last_request_file
      File.write(@last_response_file.not_nil!, response, mode: "w") if @last_response_file
    rescue ex
      Mantle::Log.error { "DetailedLogger failed to write payloads: #{ex.message}" }
    end
  end
end
