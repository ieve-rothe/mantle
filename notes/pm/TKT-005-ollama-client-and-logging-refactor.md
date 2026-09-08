---
ID: TKT-005
Title: Rename OllamaClient, Normalize Thinking, and Streamline LoggingClient Concurrency
Status: Open
Priority: High
---

## 1. User Need
Engineers integrating Mantle need a clean, unambiguous client architecture without misleading legacy names (`LlamaClient` when the wire protocol is Ollama-specific). Downstream agents and callers need raw model responses to be reliably sanitized of `<think>` tags at the adapter boundary so that reasoning thoughts are consistently available in `.thinking` while `.content` contains clean text. Furthermore, developers running concurrent client specializations (e.g. `LoggingClient(OllamaClient)` alongside other clients) need file writes to be thread/fiber safe across types without mutex isolation per generic type, and high-frequency logging needs asynchronous disk I/O via a dedicated background fiber to avoid blocking execution.

## 2. Specification
1. **Rename to `OllamaClient`**: Rename `Mantle::Clients::LlamaClient` to `Mantle::Clients::OllamaClient` in `src/mantle/clients/client.cr`. No backwards-compatibility alias is retained (breaking change for Mantle v1.0.0). Update all references in code, specs, and documentation.
2. **Normalize Thinking in Adapter Boundary**: In `OllamaClient`, run raw response content through `Mantle::Support::Text.extract_thinking` during ingestion. If the backend fails to populate native thinking fields and dumps `<think>` tags into `content`, extract them at the adapter boundary so the engine always receives clean text and normalized thinking.
3. **DRY Response Parsing**: Extract the duplicated response construction, token count extraction, and `truncated_in_thinking?` warning logic shared between `execute_stream` and `execute_standard` into private helper methods (`build_response` and `parse_token_count`).
4. **Maintain Schema Decoupling**: Keep `Mantle::Tools::Tool` as canonical internal schema; document provider adapter mapping to wire format.
5. **Fix Generic Mutex Scoping in `LoggingClient(T)`**: Move `@@file_mutex` out of generic class `LoggingClient(T)` into an unparameterized module `ReceiptWriter`. All generic client specializations writing to the same log target will share the mutex.
6. **Streamline Disk I/O**: Migrate file writes in `ReceiptWriter` to a dedicated background fiber fed by a buffered `Channel(ReceiptTask)`.
7. **Strictly Deterministic Flush**: Implement `ReceiptWriter.flush` which blocks until the channel is empty and all prior queued writes have completed writing and flushed to disk before returning.
8. **Verify Obsolete Logger Removal**: Confirm `src/mantle/support/logger.cr` remains completely removed.
9. **Document Release Notes**: Update `notes/releases/v1.0.0.md` detailing all breaking changes and migration steps for `OllamaClient` and `LoggingClient`.

## 3. Verification & Validation (V&V)
* **Verification Plan:**
  - Execute `crystal spec` in `.worktrees/mantle-tkt-005-ollama-client/`.
  - Add unit specs in `spec/client_spec.cr` verifying `OllamaClient` response parsing and `<think>` normalization.
  - Add unit specs in `spec/clients/logging_client_spec.cr` verifying concurrent writes from multiple client specializations share the lock and `ReceiptWriter.flush` blocks until channel is drained.
* **Verification Evidence:**
  - (To be recorded upon completion).
* **Validation Plan:**
  - Validate end-to-end receipt generation in JSONL format with concurrent fibers.
  - Validate `notes/releases/v1.0.0.md` contains clear migration guidance.
* **Validation Evidence:**
  - (To be recorded upon completion).

## Open Questions & Concurrency Concerns
* Concurrency concern addressed: `ReceiptWriter.flush` enqueues a flush sentinel task through the FIFO buffered channel with a sync rendezvous channel, guaranteeing strict determinism for test suites.

## 4. Revision History
* 2026-09-08: Ticket created. Scope defined for OllamaClient renaming, thinking normalization, DRY response parsing, schema decoupling, LoggingClient unparameterized mutex, and async channel worker with deterministic flush.
