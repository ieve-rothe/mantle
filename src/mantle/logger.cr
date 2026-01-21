# mantle/logger.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "file"
require "time"

module Mantle
  # Abstract class for loggers
  #
  # Defines contract that loggers must follow.
  # Abstract class was implemented to allow a 'DummyLogger' to be used for unit tests
  abstract class Logger
    # Logs a message
    #
    # - `message`: Content to be logged
    # - `label`: A category label, eg "Context Input", "Model Response", "ERROR"
    abstract def log(label : String, message : String)
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
    def initialize(@log_file : String)
      new_context
    end

    # Writes a formatted message to log file
    #
    # Rescues and prints error to STDOUT if file write fails
    #
    # - `message`: Content to be logged
    # - `label`: A category label, eg "Context Input", "Model Response", "ERROR"
    def log(label : String, message : String)
      formatted_entry = format(message, label)
      File.write(@log_file, formatted_entry, mode: "a")
    rescue ex
      puts "Logger failed to write: #{ex.message}"
    end
    #---

    def clear_log_file()
      File.write(@log_file, "", mode: "w")
    end

    def log_context(message : String)
      # Only implemented in DetailedLogger
    end

    def log_user_message(message : String)
      # Only implemented in DetailedLogger
    end

    def log_bot_message(message : String)
      # Only implemented in DetailedLogger
    end

    private def new_context()
      separator = "\n" + get_ascii_divider(:stars) + "\n"
      File.write(@log_file, separator, mode: "a")
    end
    #---

    # Formats a log entry with a UTC timestamp and label.
    private def format(message : String, label : String)
      "[#{Time.utc.to_s("%F")}] -- [#{label}] #{message}\n" + log_separator + "\n"
    end

    # Helper to draw a separator line in output
    private def log_separator
      "#{"-" * 50}"
    end
    #---

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
    #---
  end

  class DetailedLogger < FileLogger
    property context_log_file : String
    property last_user_message_file : String
    property last_bot_message_file : String

    def initialize(@log_file : String, @context_log_file : String, @last_user_message_file : String, @last_bot_message_file : String)
      super()
    end

    def log_context(message : String)
      File.write(@context_log_file, message, mode: "w")
    end

    def log_user_message(message : String)
      File.write(@last_user_message_file, message, mode: "w")
    end

    def log_bot_message(message : String)
      File.write(@last_bot_message_file, message, mode: "w")
    end
  end
end
