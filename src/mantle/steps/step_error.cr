# mantle/steps/step_error.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle
  # Represents standard domain errors that can occur during a Step execution.
  enum StepError
    # Model emitted unparseable output or empty response with no content and no tool calls.
    MalformedOutput

    # Bounded tool calling loop hit the maximum iterations limit.
    MaxIterationsReached

    # Underlying LLM client failed during transport or API communication.
    ClientFailure

    # An executed tool failed or raised a terminal error during evaluation.
    ToolExecutionFailure

    # Underlying LLM client or upstream provider rejected request due to rate limiting.
    RateLimited

    # Returns true if this error represents a transient failure eligible for retry.
    def retryable? : Bool
      client_failure? || rate_limited?
    end

    # Returns true if this error represents a terminal/unrecoverable failure.
    def terminal? : Bool
      !retryable?
    end
  end
end
