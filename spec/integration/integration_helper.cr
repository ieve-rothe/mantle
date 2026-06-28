require "../spec_helper"
require "../../src/mantle"

# ScriptedClient simulates LLM behavior by returning a sequence of predefined responses.
# It is useful for testing full lifecycle interactions without relying on a real LLM.
class ScriptedClient < Mantle::Clients::Client
  property responses : Array(Mantle::Clients::Response)
  property call_count : Int32 = 0
  property recorded_messages : Array(Array(Mantle::Message)) = [] of Array(Mantle::Message)

  def initialize(@responses : Array(Mantle::Clients::Response))
  end

  def execute(messages : Array(Mantle::Message), tools : Array(Mantle::Tools::Tool)? = nil, &on_chunk : String -> Nil) : Mantle::Clients::Response
    @recorded_messages << messages

    if @call_count >= @responses.size
      raise Exception.new("ScriptedClient ran out of predefined responses at call #{@call_count + 1}")
    end

    response = @responses[@call_count]
    @call_count += 1

    # Call on_chunk with content if present (to simulate streaming behavior)
    if content = response.content
      on_chunk.call(content)
    end

    response
  end
end
