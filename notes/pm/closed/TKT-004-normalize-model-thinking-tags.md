---
ID: TKT-004
Title: Normalize Model Thinking Tags (<think>)
Status: Closed
Priority: High
---

## 1. User Need
LLM clients often receive raw model output containing `<think>...</think>` tags embedded within response text (e.g. from DeepSeek R1 or Qwen reasoning models). Downstream components (ChatFlow, context managers, memory summarizers, subagent runners) should not see raw unparsed `<think>` tag cruft mixed into assistant content; instead, thinking should be extracted into `.thinking : String?` and `.content : String?` should always contain sanitized text.

## 2. Specification
1. Update `Mantle::Support::Text` with `extract_thinking(raw_text : String) : {String, String?}` using regex `/<think>(.*?)(?:<\/think>|\z)/m`.
2. Support closed `<think>foo</think>`, multiline tags, unclosed/truncated `<think>foo`, and tagless text, trimming surrounding newline cruft.
3. Update `Mantle::Support::Text.strip_thinking` to call `extract_thinking(raw_text)[0]`.
4. Hook normalization into client ingestion (`LlamaClient` streaming & standard parsers) and `Mantle::Clients::Response#initialize`, preferring native API thinking if present, falling back to parsed `<think>` tags.
5. Add unit and integration spec tests verifying normalization across text support, response, and client execution.

## 3. Verification & Validation (V&V)
* **Verification Plan:** Run `crystal spec` in `mantle/` to confirm all unit specs pass cleanly.
* **Verification Evidence:** Executed `crystal spec`, 289 examples, 0 failures, 0 errors.
* **Validation Plan:** Execute unit and integration specs covering standard, multiline, incomplete, tagless, and Ollama client payloads with thinking tags.
* **Validation Evidence:** `spec/mantle/support/text_spec.cr`, `spec/clients/response_spec.cr`, `spec/client_spec.cr`, and `spec/context_manager_spec.cr` passed cleanly.

## Open Questions & Concurrency Concerns
None.

## 4. Revision History
* 2026-09-08: Ticket opened for model thinking tag normalization refactor.
* 2026-09-08: Implemented `extract_thinking`, hooked client normalization in `LlamaClient` and `Response`, verified via full spec suite, closed ticket.
