# mantle/steps/step.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

require "json"
require "../clients/client"
require "../clients/message"
require "../tools/tools"
require "./step_error"
require "./step_result"

module Mantle
  # Coordinates a single or multi-turn inference step, executing LLM calls and tool loops.
  #
  # Unlike legacy flows, Step is decoupled from storage persistence and context management.
  # It consumes messages and returns a strongly-typed StepResult(String, StepError).
  class Step
    # The client used for LLM inference turns.
    property client : Mantle::Clients::Client

    # The list of tool definitions available during execution.
    property tools : Array(Mantle::Tools::Tool)

    # The maximum number of tool loop iterations permitted before terminating.
    property max_iterations : Int32

    # Status update callback handler for execution lifecycle events.
    property on_status : Proc(Symbol, Nil)?

    # Optional fallback callback for executing custom tools.
    property tool_callback : Proc(String, Hash(String, JSON::Any), String)?

    # Optional per-iteration projection hook. Invoked immediately before each
    # inference call with the current working buffer and the previous iteration's
    # response (nil on the first iteration). Returns the buffer to send.
    #
    # Note: Mantle::Message is a struct. Mutating properties in-place on elements
    # of working_messages mutates a copy. Use a #map rebuild or indexed write-back
    # (working_messages[i] = ...). On rebuild, pass `tool_call_id:` by keyword.
    property on_iteration : Proc(Array(Mantle::Message), Mantle::Clients::Response?, Array(Mantle::Message))?

    # Creates a step pipeline configured once with client, tools, limit, and status hook.
    def initialize(
      @client : Mantle::Clients::Client,
      @tools : Array(Mantle::Tools::Tool) = [] of Mantle::Tools::Tool,
      @max_iterations : Int32 = 10,
      @on_status : Proc(Symbol, Nil)? = nil,
      @tool_callback : Proc(String, Hash(String, JSON::Any), String)? = nil,
      @on_iteration : Proc(Array(Mantle::Message), Mantle::Clients::Response?, Array(Mantle::Message))? = nil,
    )
    end

    # Executes the inference loop with token streaming via block.
    #
    # Graph-isolated execution: `messages` is treated as immutable input and never modified in-place.
    # Tool execution loops append only to an isolated local working buffer (`working_messages = messages.dup`),
    # preventing internal tool exchanges from polluting the caller's context or canonical graph.
    def run(
      messages : Array(Mantle::Messages::Message),
      &block : String -> Nil
    ) : StepResult(String, StepError)
      working_messages = messages.dup
      iteration = 0
      last_thinking : String? = nil
      last_response : Mantle::Clients::Response? = nil

      loop do
        iteration += 1

        if iteration > @max_iterations
          @on_status.try &.call(:idle)
          return StepResult(String, StepError).new(
            error: StepError::MaxIterationsReached,
            thinking: last_thinking,
            iterations: iteration - 1,
            raw_response: last_response
          )
        end

        if hook = @on_iteration
          working_messages = hook.call(working_messages, last_response)
        end

        @on_status.try &.call(:thinking)

        tools_to_pass = @tools.empty? ? nil : @tools
        response = begin
          @client.execute(working_messages, tools_to_pass, &block)
        rescue ex
          @on_status.try &.call(:idle)
          err_msg = (ex.message || "").downcase
          error_kind = (err_msg.includes?("rate limit") || err_msg.includes?("429")) ? StepError::RateLimited : StepError::ClientFailure
          return StepResult(String, StepError).new(
            error: error_kind,
            thinking: last_thinking,
            iterations: iteration,
            raw_response: last_response
          )
        end

        last_response = response
        if t = response.thinking
          last_thinking = t
        end

        # Process tool calls if present
        if tool_calls = response.tool_calls
          if !tool_calls.empty?
            @on_status.try &.call(:tool_loop)

            # Record assistant turn in working context
            working_messages << Mantle::Message.new(
              role: "assistant",
              content: response.content,
              tool_calls: tool_calls
            )

            # Execute each requested tool call
            failed_execution = false
            tool_calls.each do |call|
              fn_name = call.function.name
              fn_args_raw = call.function.arguments

              tool_def = @tools.find { |t| t.function.name == fn_name }

              tool_result_str = begin
                parsed_args = JSON.parse(fn_args_raw).as_h
                if tool_def && tool_def.handler
                  tool_def.execute(parsed_args)
                elsif cb = @tool_callback
                  cb.call(fn_name, parsed_args)
                else
                  failed_execution = true
                  break
                end
              rescue ex : Mantle::Tools::TerminalToolInterrupt
                @on_status.try &.call(:idle)
                return StepResult(String, StepError).new(
                  value: ex.message || "",
                  thinking: last_thinking,
                  iterations: iteration,
                  raw_response: response
                )
              rescue ex : Mantle::Tools::TerminalToolError
                @on_status.try &.call(:idle)
                return StepResult(String, StepError).new(
                  error: StepError::ToolExecutionFailure,
                  thinking: last_thinking,
                  iterations: iteration,
                  raw_response: response
                )
              rescue ex : JSON::ParseException
                @on_status.try &.call(:idle)
                return StepResult(String, StepError).new(
                  error: StepError::MalformedOutput,
                  thinking: last_thinking,
                  iterations: iteration,
                  raw_response: response
                )
              rescue ex
                @on_status.try &.call(:idle)
                return StepResult(String, StepError).new(
                  error: StepError::ToolExecutionFailure,
                  thinking: last_thinking,
                  iterations: iteration,
                  raw_response: response
                )
              end

              working_messages << Mantle::Message.new(
                role: "tool",
                content: tool_result_str,
                tool_call_id: call.id
              )
            end

            if failed_execution
              @on_status.try &.call(:idle)
              return StepResult(String, StepError).new(
                error: StepError::ToolExecutionFailure,
                thinking: last_thinking,
                iterations: iteration,
                raw_response: response
              )
            end

            # Proceed to next iteration
            next
          end
        end

        # Final text resolution or empty output check
        if content = response.content
          @on_status.try &.call(:idle)
          return StepResult(String, StepError).new(
            value: content,
            error: nil,
            thinking: response.thinking || last_thinking,
            iterations: iteration,
            raw_response: response
          )
        else
          @on_status.try &.call(:idle)
          return StepResult(String, StepError).new(
            error: StepError::MalformedOutput,
            thinking: response.thinking || last_thinking,
            iterations: iteration,
            raw_response: response
          )
        end
      end
    end

    # Executes the inference loop synchronously without a chunk block.
    def run(
      messages : Array(Mantle::Messages::Message),
    ) : StepResult(String, StepError)
      run(messages) { |_| }
    end
  end
end
