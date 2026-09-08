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
  end
end
