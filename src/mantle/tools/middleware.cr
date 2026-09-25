# mantle/tools/middleware.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "json"
require "./tools"

class SecurityError < Exception
end

module Mantle::Tools
  class CommandFailedError < Exception
    getter exit_code : Int32

    def initialize(@exit_code : Int32, message : String)
      super(message)
    end
  end

  module Middleware
    abstract class Base
      abstract def call(
        tool_name : String,
        args : Hash(String, JSON::Any),
        next_handler : Proc(Hash(String, JSON::Any), String)
      ) : String
    end

    # Traps only whitelisted operational errors caused by model input or environment state.
    # Developer/system errors (NilAssertionError, TypeCastError, IndexError, etc.) are NOT caught.
    class ExceptionTrapping < Base
      def call(
        tool_name : String,
        args : Hash(String, JSON::Any),
        next_handler : Proc(Hash(String, JSON::Any), String)
      ) : String
        begin
          next_handler.call(args)
        rescue ex : SecurityError
          "[SecurityError: #{ex.message}]"
        rescue ex : File::Error
          "[FileError: #{ex.message}]"
        rescue ex : ArgumentError
          "[ArgumentError: #{ex.message}]"
        rescue ex : JSON::ParseException
          "[JSONError: #{ex.message}]"
        rescue ex : CommandFailedError
          "[CommandFailed: #{ex.message}]"
        end
      end
    end

    # Wraps a single Tool with a pipeline of middlewares.
    # The first middleware in the array is the outermost wrapper.
    def self.wrap(tool : Mantle::Tools::Tool, middlewares : Array(Base)) : Mantle::Tools::Tool
      return tool if middlewares.empty?

      orig_handler = tool.handler || ->(args : Hash(String, JSON::Any)) {
        {error: "No handler for #{tool.function.name}"}.to_json
      }

      composed_handler = middlewares.reverse.reduce(orig_handler) do |acc_handler, mw|
        ->(args : Hash(String, JSON::Any)) {
          mw.call(tool.function.name, args, acc_handler)
        }
      end

      wrapped = tool.dup
      wrapped.handler = composed_handler
      wrapped
    end

    # Wraps an array of Tools with the specified middlewares.
    def self.wrap_all(tools : Array(Mantle::Tools::Tool), middlewares : Array(Base)) : Array(Mantle::Tools::Tool)
      return tools if middlewares.empty?
      tools.map { |tool| wrap(tool, middlewares) }
    end
  end
end

alias ToolMiddleware = Mantle::Tools::Middleware

require "./middleware/cyclic_read_breaker"
