# mantle/steps/step_result.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "../clients/client"
require "./step_error"

module Mantle
  # Raised when attempting to unwrap a StepResult that contains an error or has no value.
  class StepUnwrapError < Exception
  end

  # Represents the strongly-typed outcome of a Step execution.
  #
  # Holds either a successful value of type `T` or a typed domain error `E` (`StepError`).
  class StepResult(T, E)
    # The successful payload (e.g. String for raw text, or a domain struct).
    property value : T?

    # The typed domain error.
    property error : E?

    # Sanitized internal reasoning extracted from <think> tags or native API fields.
    property thinking : String?

    # Number of loop cycles taken (especially for tool evaluation).
    property iterations : Int32

    # Underlying adapter response metadata.
    property raw_response : Mantle::Clients::Response?
    property error_message : String?

    def initialize(
      @value : T? = nil,
      @error : E? = nil,
      @thinking : String? = nil,
      @iterations : Int32 = 0,
      @raw_response : Mantle::Clients::Response? = nil,
      @error_message : String? = nil,
    )
    end

    # Returns true if execution succeeded with no error.
    def ok? : Bool
      @error.nil?
    end

    # Returns true if an error occurred during execution.
    def err? : Bool
      !ok?
    end

    # Returns @value or raises StepUnwrapError.
    def unwrap : T
      if val = @value
        if ok?
          val
        else
          raise StepUnwrapError.new("Attempted to unwrap failed StepResult: #{@error}")
        end
      else
        raise StepUnwrapError.new(@error ? "Attempted to unwrap failed StepResult: #{@error}" : "Attempted to unwrap StepResult with nil value")
      end
    end

    # Factory helper for successful result
    def self.ok(v : U, thinking : String? = nil, iterations : Int32 = 0, raw_response : Mantle::Clients::Response? = nil) forall U
      StepResult(U, StepError).new(value: v, thinking: thinking, iterations: iterations, raw_response: raw_response)
    end

    # Factory helper for error result
    def self.error(e : F, thinking : String? = nil, iterations : Int32 = 0, raw_response : Mantle::Clients::Response? = nil) forall F
      StepResult(String, F).new(error: e, thinking: thinking, iterations: iterations, raw_response: raw_response)
    end
  end
end
