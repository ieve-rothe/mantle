# mantle/squishifiers.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Provides functions to create 'squishifier' procs for use in memory management.
#
# Squishification refers to the summarization or compression of conversation messages
# into system memory.
module Mantle::Support::Squishifiers
  # Builds a basic summarization proc that compresses an array of messages into a single string.
  #
  # Uses the specified *client* to run the summarization LLM call with *system_prompt*.
  # Returns a `Proc(Array(String), String)` that takes an array of messages and returns the summary.
  def self.build_basic_summarizer(
    client : Mantle::Clients::Client,
    system_prompt : String = "Extract factual data from the following conversation log into a concise bulleted list.",
  ) : Proc(Array(String), String)
    ->(messages : Array(String)) : String {
      # Build the chat messages array
      user_content = messages.join("\n")

      chat_messages = [
        {"role" => "system", "content" => system_prompt},
        {"role" => "user", "content" => user_content},
      ]

      response = client.execute(chat_messages)

      return (response.content || "").strip
    }
  end
end
