---
ID: TKT-005
Title: Rename OllamaClient, Normalize Thinking, and Streamline LoggingClient Concurrency
Status: Closed
Priority: High
---

## 1. User Need
Engineers integrating Mantle need a clean, unambiguous client architecture without misleading legacy names (`LlamaClient` when the wire protocol is Ollama-specific). Downstream agents and callers need raw model responses to be reliably sanitized of `<think>` tags at the adapter boundary so that reasoning thoughts are consistently available in `.thinking` while `.content` contains clean text. Furthermore, developers running concurrent client specializations (e.g. `LoggingClient(OllamaClient)` alongside other clients) need file writes to be thread/fiber safe across types without mutex isolation per generic type, and high-frequency logging needs asynchronous disk I/O via a dedicated background fiber to avoid blocking execution.

## 2. Specification
1. **Rename to `OllamaClient`**: Rename `Mantle::Clients::LlamaClient` to `Mantle::Clients::OllamaClient` in `src/mantle/clients/client.cr`. No backwards-compatibility alias is retained (breaking change for Mantle v1.0.0). Update all references in code, specs, and documentation.
2. **Normalize Thinking in Adapter Boundary**: In `OllamaClient`, run raw response content through `Mantle::Support::Text.extract_thinking` during ingestion. If the backend fails to populate native thinking fields and dumps `<think>` tags into `content`, extract them at the adapter boundary so the engine always receives clean text and normalized thinking.
3. **DRY Response Parsing**: Extract the duplicated response construction, token count extraction, and `truncated_in_thinking?` warning logic shared between `execute_stream` and `execute_standard` into private helper methods (`build_response` and `parse_token_count`).
4. **Maintain Schema Decoupling**: Keep `Mantle::Tools::Tool` as canonical internal schema; document provider adapter mapping to wire format.
5. **Fix Generic Mutex Scoping in `LoggingClient(T)`**: Move `@@file_mutex` out of generic class `LoggingClient(T)` into an unparameterized module `ReceiptWriter`.
6. **Streamline Disk I/O**: Migrate file writes in `ReceiptWriter` to a dedicated background fiber fed by a buffered `Channel(ReceiptTask)` with atomic single-worker start (`Atomic(Bool)`).
7. **Strictly Deterministic Flush**: Implement `ReceiptWriter.flush` which blocks until the channel is empty and all prior queued writes have completed writing and flushed to disk before returning.
8. **Verify Obsolete Logger Removal**: Confirmed `src/mantle/support/logger.cr` remains completely removed.
9. **Document Release Notes**: Update `notes/releases/v1.0.0.md` detailing all breaking changes and migration steps for `OllamaClient` and `LoggingClient`.

## 3. Verification & Validation (V&V)
* **Verification Plan:**
  - Execute `crystal spec` in isolated worktree and verify all unit and integration tests.
  - Add unit specs in `spec/client_spec.cr` verifying `OllamaClient` response parsing and `<think>` normalization.
  - Add unit specs in `spec/clients/logging_client_spec.cr` verifying concurrent writes from multiple client specializations share the lock and `ReceiptWriter.flush` blocks until channel is drained.
* **Verification Evidence:**
  - `crystal spec` executed successfully: 291 examples, 0 failures, 0 errors, 0 pending.
  - `spec/client_spec.cr` executed successfully: 22 examples, 0 failures, 0 errors.
  - `spec/clients/logging_client_spec.cr` executed successfully: 8 examples, 0 failures, 0 errors.
  - `spec/integration/mock_server_spec.cr` executed successfully: 5 examples, 0 failures, 0 errors.
* **Validation Plan:**
  - Confirm concurrent client specializations write cleanly without file corruption.
  - Confirm breaking changes are comprehensively documented in `notes/releases/v1.0.0.md`.
* **Validation Evidence:**
  - Concurrent multi-fiber specs in `spec/clients/logging_client_spec.cr` verified concurrent output from distinct client types.
  - `notes/releases/v1.0.0.md` updated with sections 5 and 6 explaining breaking changes, rationales, and migration code.

## Open Questions & Concurrency Concerns
* Concurrency concern addressed: `ReceiptWriter.flush` enqueues a flush sentinel task through the FIFO buffered channel with a sync rendezvous channel, guaranteeing strict determinism for test suites.
* File I/O serialized safely through a single background worker fiber started atomically via `Atomic(Bool)#swap(true)`.

## 4. Outcome & Integration
* **Status**: CLOSED
* **Merged Commits**:
  - `eb87b80` refactor(client): rename OllamaClient, DRY response parsing, normalize thinking, and streamline LoggingClient I/O (TKT-005)
  - `73ae89e` [chore] tool format
  - `e083c5f` refactor(logging): streamline ReceiptWriter with atomic worker start and deterministic flush in specs
* **Summary**: Worktree `.worktrees/mantle-tkt-005-ollama-client` successfully integrated into `main` and cleanly torn down.

## 5. Revision History
* 2026-09-08: Ticket created. Scope defined for OllamaClient renaming, thinking normalization, DRY response parsing, schema decoupling, LoggingClient unparameterized mutex, and async channel worker with deterministic flush.
* 2026-09-08: Implementation completed in worktree, all 291 specs verified passing, branch merged to `main`, worktree pruned, ticket closed.
