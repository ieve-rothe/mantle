---
ID: TKT-002
Title: MarkdownFormatter Migration & Refactor
Status: Open
Priority: High
---

## 1. User Need
Users interacting with Salamander and developers using Mantle need a clean separation between the core LLM engine and terminal presentation concerns. Currently, `MarkdownFormatter` resides in Mantle's support directory (`Mantle::Support::MarkdownFormatter`), which leaks terminal styling escape codes into the core engine library. Additionally, the existing formatter corrupts code blocks containing markdown characters (e.g. `*`, `#`), suffers from ANSI color bleed on nested tags, exhibits sub-optimal performance due to sequential regex string replacement allocations, and lacks incremental streaming support. Relocating `MarkdownFormatter` to `Salamander::UI::MarkdownFormatter` and refactoring its lexing and rendering pipeline will ensure a clean architecture, robust rendering, and smooth streaming UX.

## 2. Specification
1. **Repository & Namespace Relocation:**
   - Relocate `markdown_formatter.cr` from `mantle/src/mantle/support/` to `salamander/src/salamander/ui/` (or presentation layer).
   - Move associated specs and benchmarks to Salamander (`salamander/spec/ui/markdown_formatter_spec.cr` and `salamander/benchmarks/`).
   - Update namespace from `Mantle::Support::MarkdownFormatter` to `Salamander::UI::MarkdownFormatter`.
   - Audit `mantle` codebase and remove any lingering references/requires to the formatter.
   - Update `mantle.cr` root export to ensure no terminal styling leaks into the core engine.

2. **Parser & Rendering Bug Fixes:**
   - **Code Block Protection:** Invert processing order. Extract triple-backtick code blocks (` ``` `) and inline code (`` ` ``) first into temporary placeholder tokens (e.g., `\x00CODE_BLOCK_0\x00`). Apply inline/prose formatting (bold, italic, links, headers, blockquotes) exclusively to non-code text. Re-inject syntax-highlighted or styled code blocks last so markdown characters inside code (`*`, `_`, `#`) are never corrupted.
   - **ANSI Style Reset Bleeding (`\e[0m`):** Stop using hard `\e[0m` resets on inner nested elements (e.g., `**bold**` inside a `# Header`). Ensure nested spans restore their immediate parent styling rather than resetting the entire line to terminal default.

3. **Performance & Allocation Optimization:**
   - Replace 7 sequential `gsub` heap allocations with a single-pass token scanner or a single `String.build` buffer sweep.
   - Benchmark memory churn during full buffer replacement on long-form (1,000+ token) model outputs.

4. **Streaming UX Architecture:**
   - Evaluate replacing post-stream full-buffer replacement with an incremental state-machine lexer that formats tokens in-flight.
   - Ensure full-buffer rewrite handles terminal scrollback cleanly without visual cursor flickering or line drops.

## 3. Verification & Validation (V&V)
* **Verification Plan:**
  - Run `crystal spec` in `mantle/` — confirm all specs pass without referencing `MarkdownFormatter`.
  - Run `crystal spec` in `salamander/` — verify all relocated and updated `MarkdownFormatter` specs pass.
  - Verify code block protection: markdown characters (`*`, `_`, `#`) inside code blocks and inline code remain untouched after formatting.
  - Verify ANSI style stack: nested formatted elements restore parent color/style context instead of hard `\e[0m` terminal reset.
  - Run benchmarks in `salamander/benchmarks/` to verify memory allocation reductions.
* **Verification Evidence:** [Pending]
* **Validation Plan:**
  - Perform interactive terminal test in Salamander during LLM response streaming to verify cursor stability, lack of flicker, and clean line scrollback.
* **Validation Evidence:** [Pending]

## Open Questions & Concurrency Concerns
* Should `Salamander::UI::MarkdownFormatter` support custom ANSI color scheme configuration for user themes?
* What state machine approach works best for in-flight incremental token formatting during active LLM streaming response chunks?

## 4. Revision History
* 2026-09-08: Ticket created from Migration & Refactor Checklist.
---
