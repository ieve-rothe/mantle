require "../spec_helper"
require "../../src/mantle"

# ScriptedClient simulates LLM behavior by returning a sequence of predefined responses.
# It is useful for testing full lifecycle interactions without relying on a real LLM.
class ScriptedClient < Mantle::Client
  property responses : Array(Mantle::Response)
  property call_count : Int32 = 0
  property recorded_messages : Array(Array(Hash(String, String))) = [] of Array(Hash(String, String))

  def initialize(@responses : Array(Mantle::Response))
  end

  def execute(messages : Array(Hash(String, String)), tools : Array(Mantle::Tool)? = nil) : Mantle::Response
    @recorded_messages << messages

    if @call_count >= @responses.size
      raise Exception.new("ScriptedClient ran out of predefined responses at call #{@call_count + 1}")
    end

    response = @responses[@call_count]
    @call_count += 1
    response
  end
end
