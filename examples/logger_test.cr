# examples/logger_test.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Basic example / test harness for the FileLogger.
# Demonstrates formatting capabilities.

require "../src/mantle.cr"

# Initializing a FileLogger creates the log file if it doesn't exist.
# The `include_thinking` flag tells the logger whether to strip out
# `<think>` blocks or include them in the log output.
logger = Mantle::FileLogger.new("logger_test_log.txt", "User", "Assistant", include_thinking: true)

# Manually clears the log file
logger.clear_log_file

# Basic logging writes an entry prefixed with the label and formatted cleanly
logger.log("test", "test_label")
logger.log("Because initialize is the process of building an instance, self inside that block already refers to the instance. Calling the method simply as new_context (without the FileLogger. prefix) would point the compiler to the instance method you defined.
Why the Instance Scope Matters

The use of @log_file inside new_context is the key reason it has to be an instance method. Instance variables don't exist in the class-level scope—the blueprint doesn't have a specific file path assigned to it, only the specific FileLogger object you just created does.", "test_label")

puts "Check logger_test_log.txt for formatted output."
