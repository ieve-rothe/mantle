---
ID: TKT-007
Title: Session Turn Pipeline, Ephemeral Injections, and Graph-Isolated Step Execution
Status: Open
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
     - Retrying the turn must not duplicate the trigger message in the canonical graph.
5. **Audit Receipt Integration**:
   - Create `src/mantle/clients/receipt_writer.cr` with `EphemeralInjections` structure and `ReceiptTask`.
   - `ReceiptTask` captures `ephemeral_injections` (including LTM state).
   - `LoggingClient` serializes `"ephemeral_injections"` in the JSONL audit receipt.
6. **Session Turn Orchestrator (`Mantle::Session`)**:
   - Implement `Mantle::Session` in `src/mantle/session.cr`.
   - Turn execution: `#run_turn(trigger, system_injections, pre_history_injections, tail_injections, is_retry = false, &stream_block)`.
   - Queue consumer: `#consume_queue(inbox, outbox, stream_channel)` with retryable backoff and terminal dead-lettering.
7. **Examples Modernization**:
   - Update `examples/02_chat_flow.cr` and `examples/03_tool_calling.cr` to use `Mantle::Session`.
   - Add `examples/04_session.cr` demonstrating mixed provenance, spatial injections, and retry handling.
8. **Architecture Documentation**:
   - Document changes in `notes/releases/v1.0.0.md`.
   - Add architecture note `notes/architecture/context_assembly_and_injections.md`.

## 3. Verification & Validation (V&V)
* **Verification Plan:**
  - Execute specs in isolated worktree `.worktrees/mantle-tkt-007-session-step-pipeline`.
  - `spec/mantle/storage/context_manager_spec.cr`: test spatial injection ordering, graph immutability during projection, and `<<` operator.
  - `spec/mantle/steps/step_spec.cr`: test input isolation and `StepError` taxonomy (`retryable?` vs `terminal?`).
  - `spec/mantle/session_spec.cr`: test full turn lifecycle, retry idempotency without trigger duplication, and queue routing.
  - `spec/clients/logging_client_spec.cr`: test JSONL receipt capturing `ephemeral_injections` and LTM.
  - Run full suite: `crystal spec`.
  - Check formatting: `crystal tool format --check`.
* **Verification Evidence:**
  - (To be recorded upon completion).
* **Validation Plan:**
  - Verify complete removal of legacy `current_view` and invisible append methods.
  - Verify all examples compile and run cleanly with `Session`.
  - Verify release notes in `notes/releases/v1.0.0.md` and architecture note in `notes/architecture/context_assembly_and_injections.md`.
* **Validation Evidence:**
  - (To be recorded upon completion).

## Open Questions & Concurrency Concerns
* `Mantle::Session` is documented as single-caller / thread-safe per session instance; daemon architectures manage concurrent worker isolation per session ID.

## 4. Revision History
* 2026-09-08: Ticket created for Session Turn Pipeline, Ephemeral Injections, and Graph-Isolated Step Execution.
---
