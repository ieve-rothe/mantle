---
ID: TKT-007
Title: Session Turn Pipeline, Ephemeral Injections, and Graph-Isolated Step Execution
Status: Closed
Priority: High
---

## 1. User Need
Autonomous agent systems, daemons, and chat applications built with Mantle require a cleanly decoupled execution lifecycle where context orchestration, state persistence, ephemeral prompt construction, and LLM inference do not bleed together. When an agent or daemon runs a turn or consumes from an input queue:
1. Canonical conversation history must strictly track persistent state without transient/ephemeral nudges polluting the graph.
2. Ephemeral metadata (identity reminders, temporal data, dev nudges) must be deterministically placed into spatial injection zones during view projection and accurately captured in audit receipts.
3. Step execution (`Mantle::Step`) must remain a graph-isolated transform that executes turns and tool loops without mutating the canonical context graph or external storage.
4. The turn orchestrator (`Mantle::Session`) must guarantee idempotency across retryable failures (e.g. network disconnects or rate limits), ensuring trigger messages are never duplicated in the canonical graph upon retry.
5. Storage and session primitives must offer ergonomic message appending (`<<`) supporting mixed provenance (user prompts as well as daemon/system timer events).

## 2. Specification
1. **Clean v1.0.0 Baseline (No Backward Compatibility)**:
   - Completely remove legacy `ContextManager#current_view(ephemeral_blocks)` and `@pending_invisible_append`.
   - Eliminate "ephemeral overlays" and "invisible appends" nomenclature in favor of **Ephemeral Injections**.
2. **Spatial Ephemeral Injections (`ContextManager#project_view`)**:
   - `project_view(system_injections = [], pre_history_injections = [], tail_injections = []) : Array(Mantle::Message)`
   - Assembly order: `[Base System Prompt] -> [System Injections] -> [Long-Term Memory View] -> [Pre-History Injections] -> [Conversation History] -> [Tail Injections]`.
   - String overload support converting raw strings into `system` role messages.
   - Zero mutation of canonical context graph during view projection.
3. **Ergonomic Message Appending (`<<`) & Role Generalization**:
   - Support `<<(message : String | Mantle::Message) : self` on `ContextStore`, `ContextManager`, and `Session`.
   - Strings default to `user` role; `Mantle::Message` preserves explicit roles (e.g., `system` for cron/timer triggers).
   - Canonical methods: `add_user_message(content : String)` and `add_assistant_message(content : String, tool_calls = nil)`.
4. **Error Taxonomy & Idempotency Contract**:
   - Extend `Mantle::StepError` with `RateLimited` variant and predicate methods:
     - `retryable?`: `ClientFailure`, `RateLimited`.
     - `terminal?`: `MalformedOutput`, `MaxIterationsReached`, `ToolExecutionFailure`.
   - In `Mantle::Session#run_turn`:
     - If retryable failure occurs, the trigger message remains committed to the graph.
     - Retrying the turn (`is_retry = true` or matching last message) must not duplicate the trigger message in the canonical graph.
5. **Audit Receipt Integration**:
   - Created `src/mantle/clients/receipt_writer.cr` with `EphemeralInjections` structure and `ReceiptTask`.
   - `ReceiptTask` captures `ephemeral_injections` (including LTM state).
   - `LoggingClient` serializes `"ephemeral_injections"` in the JSONL audit receipt.
6. **Session Turn Orchestrator (`Mantle::Session`)**:
   - Implemented `Mantle::Session` in `src/mantle/session.cr`.
   - Turn execution: `#run_turn(trigger, system_injections, pre_history_injections, tail_injections, is_retry = false, &stream_block)`.
   - Queue consumer: `#consume_queue(inbox, outbox, stream_channel)` with retryable backoff and terminal dead-lettering.
7. **Examples Modernization**:
   - Updated `examples/02_chat_flow.cr` and `examples/03_tool_calling.cr` to use `Mantle::Session` and `project_view`.
   - Added `examples/04_session.cr` demonstrating mixed provenance, spatial injections, and retry handling.
   - Fixed obsolete logger and context view calls in `basic_app.cr`, `tool_calling_app.cr`, and `summarizer_test.cr`.
8. **Architecture Documentation**:
   - Documented breaking changes in `notes/releases/v1.0.0.md`.
   - Added architecture note `notes/architecture/context_assembly_and_injections.md`.

## 3. Verification & Validation (V&V)
* **Verification Evidence:**
  - `crystal spec`: **301 examples, 0 failures, 0 errors, 0 pending** passed cleanly.
  - `crystal tool format --check`: clean pass across the entire codebase.
  - All examples (`01_basic_client.cr`, `02_chat_flow.cr`, `03_tool_calling.cr`, `04_session.cr`, `basic_app.cr`, `tool_calling_app.cr`, `summarizer_test.cr`) compile cleanly with `crystal build --no-codegen`.
* **Validation Evidence:**
  - Zero references to legacy `current_view` on `ContextManager` or `@pending_invisible_append`.
  - Architecture note `notes/architecture/context_assembly_and_injections.md` created with ASCII pipeline diagram, spatial zone descriptions, and idempotency guarantees.
  - Release notes in `notes/releases/v1.0.0.md` updated with Section 8 detailing migration paths and code samples.
  - Worktree merged to `main` (commit `259d970`), branch deleted, worktree removed and pruned.

## 4. Revision History
* 2026-09-08: Ticket opened for Session Turn Pipeline, Ephemeral Injections, and Graph-Isolated Step Execution.
* 2026-09-08: Implementation, verification, teardown, and documentation complete. Status moved to Closed.
---
