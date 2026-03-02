# mantle/squishifiers.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Creates 'squishifier' procs for use in memory management.
# Squishification is summarization / compression of messages into system memory

module Mantle::Squishifiers
    def self.build_basic_summarizer(client : Client) : Proc(Array(String), String)
        -> (messages : Array(String)) : String {
            prompt = "Extract factual data from this log into a bulleted list:\n"
            prompt += messages.join("\n")

            response = client.execute(prompt)

            return response.strip
        }
    end
end