# mantle/text.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle::Support
  # Provides text manipulation utilities for Mantle.
  module Text
    extend self

    # Regex used to match thinking blocks that may span multiple lines
    THINKING_REGEX = /<think>.*?<\/think>/m

    # Removes `<think>...</think>` blocks and their contents from the given string.
    def strip_thinking(msg : String) : String
      msg.gsub(THINKING_REGEX, "")
    end
  end
end
