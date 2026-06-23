# mantle/markdown_formatter.cr
# Copyright (C) 2026 Cam Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.

module Mantle::Support
  # Provides a lightweight terminal formatter that replaces Markdown syntax
  # with ANSI escape codes for improved readability in standard terminal environments.
  module MarkdownFormatter
    extend self

    # Represents the regex used to match bold markdown syntax.
    BOLD_REGEX = /\*\*([^*]+)\*\*/
    # Represents the regex used to match italic markdown syntax.
    ITALIC_REGEX = /(?<!\w)\*([^*]+)\*(?!\w)/
    # Represents the regex used to match code blocks.
    CODE_BLOCK_REGEX = /```([\s\S]*?)```/
    # Represents the regex used to match inline code.
    INLINE_CODE_REGEX = /`([^`]+)`/
    # Represents the regex used to match headers.
    HEADER_REGEX = /^(\#{1,6})\s+([^\n]+)$/m
    # Represents the regex used to match markdown links.
    LINK_REGEX = /\[([^\]\[]+)\]\(([^)]+)\)/
    # Represents the regex used to match blockquotes.
    BLOCKQUOTE_REGEX = /^>\s+([^\n]+)$/m

    # Formats a markdown string *text* by converting markdown syntax elements to ANSI escape codes.
    #
    # Supported elements: `**bold**`, `*italic*`, `# Headers`, `` `inline code` ``, ` ```code blocks``` `,
    # `> blockquotes`, and `[links](url)`.
    #
    # Sequential `gsub` calls are used to support nested markdown elements (e.g., bold within a header).
    #
    # ```
    # MarkdownFormatter.format("**Hello**") # => "\e[1;97mHello\e[0m"
    # ```
    def format(text : String) : String
      # Start with the initial text; sequential gsub calls will return new string instances.
      # We avoid an explicit .dup here as the first .gsub will create a new string if matches are found.
      formatted = text.gsub(BOLD_REGEX) { "\e[1;97m#{$~[1]}\e[0m" }

      # *italic* -> Italicized text (avoids matching within words like snake_case or bold overlap)
      formatted = formatted.gsub(ITALIC_REGEX) { "\e[3m#{$~[1]}\e[0m" }

      # ```code blocks``` -> Muted gray background
      formatted = formatted.gsub(CODE_BLOCK_REGEX) { "\e[48;5;236m#{$~[1]}\e[0m" }

      # `inline code` -> Muted gray background
      formatted = formatted.gsub(INLINE_CODE_REGEX) { "\e[48;5;236m#{$~[1]}\e[0m" }

      # Headers -> Cyan, bold text
      formatted = formatted.gsub(HEADER_REGEX) { "\e[1;36m#{$~[1]} #{$~[2]}\e[0m" }

      # [Links](url) -> Blue text with underlined URL
      formatted = formatted.gsub(LINK_REGEX) { "\e[34m#{$~[1]}\e[0m (\e[4;34m#{$~[2]}\e[0m)" }

      # > Blockquotes -> Gray, italicized text
      formatted = formatted.gsub(BLOCKQUOTE_REGEX) { "\e[3;90m> #{$~[1]}\e[0m" }

      formatted
    end
  end
end
