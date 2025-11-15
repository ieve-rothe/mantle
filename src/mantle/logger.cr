# mantle/logger.cr

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
        abstract def log(message : String, label : String, file : String)
    end

    # Concrete logger to write formatted messages to log file
    #
    # Formats messages with a timestamp and writes to file.
    class FileLogger
        # Path to log file on disk
        property log_file : String

        # Creates a new FileLogger
        #
        # - `log_file`: Path to file where logs will be appended
        def initialize(@log_file : String)
        end

        # Writes a formatted message to log file
        #
        # Rescues and prints error to STDOUT if file write fails
        #
        # - `message`: Content to be logged
        # - `label`: A category label, eg "Context Input", "Model Response", "ERROR"
        def log(message : String, label : String)
            formatted_entry = format(message, label)
            File.append(@log_file, formatted_entry)
        rescue ex
            puts "Logger failed to write: #{ex.message}"
        end

        # -----
        
        # Formats a log entry with a UTC timestamp and label.
        private def format(message : String, label : String)
            "[#{Time.utc.to_s_iso8601}] -- [#{label}] -- #{message}"
        end
    end
end