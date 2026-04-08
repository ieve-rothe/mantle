# mantle/markdown_formatter.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle
  # A lightweight terminal formatter that replaces Markdown syntax
  # with ANSI escape codes for improved readability in standard terminal environments.
  module MarkdownFormatter
    extend self

    # Formats a markdown string by converting markdown syntax elements to ANSI escape codes.
    # Supported elements: **bold**, *italic*, # Headers, `inline code`, ```code blocks```,
    # > blockquotes, and [links](url).
    def format(text : String) : String
      formatted = text.dup

      # **bold** -> Bright white, bold text
      formatted = formatted.gsub(/\*\*([^*]+)\*\*/) { "\e[1;97m#{$~[1]}\e[0m" }

      # *italic* -> Italicized text (avoids matching within words like snake_case or bold overlap)
      formatted = formatted.gsub(/(?<!\w)\*([^*]+)\*(?!\w)/) { "\e[3m#{$~[1]}\e[0m" }

      # ```code blocks``` -> Muted gray background
      formatted = formatted.gsub(/```([\s\S]*?)```/) { "\e[48;5;236m#{$~[1]}\e[0m" }

      # `inline code` -> Muted gray background
      formatted = formatted.gsub(/`([^`]+)`/) { "\e[48;5;236m#{$~[1]}\e[0m" }

      # Headers -> Cyan, bold text
      formatted = formatted.gsub(/^(\#{1,6})\s+([^\n]+)$/m) { "\e[1;36m#{$~[1]} #{$~[2]}\e[0m" }

      # [Links](url) -> Blue text with underlined URL
      formatted = formatted.gsub(/\[([^\]\[]+)\]\(([^)]+)\)/) { "\e[34m#{$~[1]}\e[0m (\e[4;34m#{$~[2]}\e[0m)" }

      # > Blockquotes -> Gray, italicized text
      formatted = formatted.gsub(/^>\s+([^\n]+)$/m) { "\e[3;90m> #{$~[1]}\e[0m" }

      formatted
    end
  end
end
