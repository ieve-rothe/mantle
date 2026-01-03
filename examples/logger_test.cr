# examples/basic_app.cr
# Copyright (C) 2025 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Basic example / test harness application
# (Stub)

require "../src/mantle.cr"



logger = Mantle::FileLogger.new("basic_app_log.txt")
logger.log("test", "test_label")
logger.log("Because initialize is the process of building an instance, self inside that block already refers to the instance. Calling the method simply as new_context (without the FileLogger. prefix) would point the compiler to the instance method you defined.
Why the Instance Scope Matters

The use of @log_file inside new_context is the key reason it has to be an instance method. Instance variables don't exist in the class-level scope—the blueprint doesn't have a specific file path assigned to it, only the specific FileLogger object you just created does.", "test_label")