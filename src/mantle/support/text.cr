# mantle/text.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle::Support
  # Provides text manipulation utilities for Mantle.
  module Text
    extend self

    # Captures content inside <think> tags; also matches unclosed blocks if truncated
    THINKING_EXTRACTION_REGEX = /<think>(.*?)(?:<\/think>|\z)/m

    # Splits raw output into {clean_content, thinking_block}
    def extract_thinking(raw_text : String) : {String, String?}
      matches = raw_text.scan(THINKING_EXTRACTION_REGEX)
      if matches.empty?
        {raw_text.strip, nil}
      else
        thinking_parts = matches.map { |m| m[1].strip }.reject(&.empty?)
        thinking = thinking_parts.empty? ? nil : thinking_parts.join("\n\n")
        clean_content = raw_text.gsub(THINKING_EXTRACTION_REGEX, "").strip
        {clean_content, thinking}
      end
    end

    # Removes `<think>...</think>` blocks and their contents from the given string.
    def strip_thinking(raw_text : String) : String
      extract_thinking(raw_text)[0]
    end
  end
end
