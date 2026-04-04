# mantle/squishifiers.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Creates 'squishifier' procs for use in memory management.
# Squishification is summarization / compression of messages into system memory

module Mantle::Squishifiers
    def self.build_basic_summarizer(client : Client) : Proc(Array(String), String)
        -> (messages : Array(String)) : String {
            # Build the chat messages array
            system_prompt = "Extract factual data from the following conversation log into a concise bulleted list."
            user_content = messages.join("\n")

            chat_messages = [
                {"role" => "system", "content" => system_prompt},
                {"role" => "user", "content" => user_content}
            ]

            response = client.execute(chat_messages)

            return response.strip
        }
    end
end