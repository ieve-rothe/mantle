# The tests failed because when we use `m[1]` in the block for `gsub(regex)` in Crystal, `m` is actually the MATCHED STRING, not the MatchData!
# Ah! `gsub(Regex) { |m| ... }` yields a String `m` (the full match string, e.g., "**bold**").
# So `m[1]` returns the character at index 1 of the matched string, which is `*` for "**bold**".
# That's why we MUST use `$~[1]`!
# Let's verify this.
text = "This is **bold** text"
result = text.gsub(/\*\*([^*]+)\*\*/) { |m| m.class.name }
puts result
