---
ID: TKT-006
Title: Refactor Flow into Step, Introduce StepResult(T, E), and Remove Legacy Flow Hierarchy
Status: Closed
Priority: High
---

## 1. User Need
Developers building autonomous agent systems with Mantle need a composable, decoupled inference pipeline that executes turns and returns strongly-typed results (`Mantle::StepResult(T, E)`) rather than relying on global/external callbacks or raising runtime exceptions during normal tool loops. The legacy `Flow` hierarchy (`Flow`, `ChatFlow`, `ToolEnabledChatFlow`) coupled storage context management with LLM inference, lacked strong typing for execution outcomes, and imposed excessive parameter complexity. Developers need a streamlined `Mantle::Step` pipeline with clean top-level namespacing (`Mantle::Step`), pure message-in/result-out semantics, bounded iteration safety, and explicit domain errors (`Mantle::StepError`).

## 2. Specification
1. **Remove Legacy `Flow` Hierarchy**: Completely remove `Mantle::Flows::Flow`, `Mantle::Flows::ChatFlow`, `Mantle::Flows::ToolEnabledChatFlow`, and `src/mantle/flows/` with no backward compatibility for v1.0.0.
2. **Top-Level Clean Namespacing**: Directly expose `Mantle::Step`, `Mantle::StepResult(T, E)`, `Mantle::StepError`, and `Mantle::StepUnwrapError` under `Mantle` namespace without nested module clutter.
3. **Domain Error Enum (`Mantle::StepError`)**: Define in `src/mantle/steps/step_error.cr` with variants:
   - `MalformedOutput`
   - `MaxIterationsReached`
   - `ClientFailure`
   - `ToolExecutionFailure`
4. **Outcome Type (`Mantle::StepResult(T, E)`)**: Implement in `src/mantle/steps/step_result.cr`:
   - Properties: `value : T?`, `error : E?`, `thinking : String?`, `iterations : Int32`, `raw_response : Mantle::Clients::Response?`.
   - Convenience methods: `ok? : Bool`, `err? : Bool`, `unwrap : T` (raises `StepUnwrapError`).
   - Factory methods: `self.ok(...)`, `self.error(...)`.
5. **Execution Pipeline (`Mantle::Step`)**: Implement in `src/mantle/steps/step.cr`:
   - `initialize(@client : Mantle::Clients::Client, @tools : Array(Mantle::Tools::Tool) = [] of Mantle::Tools::Tool, @max_iterations : Int32 = 10, @on_status : Proc(Symbol, Nil)? = nil)`
   - Pure execution: `run(messages : Array(Mantle::Message), &block : String -> Nil) : StepResult(String, StepError)` and overload `run(messages : Array(Mantle::Message))`.
   - Pure message-in / result-out boundary: does not mutate external storage or disk state.
   - Status hooks: dispatches `:awaiting_inference`, `:calling_tools`, `:idle` via instance `@on_status`.
   - Bounded tool execution: immediately returns `StepResult.error(StepError::MaxIterationsReached)` if loop exceeds `@max_iterations`.
6. **Executable Tools & Schema Compatibility**:
   - Update `Mantle::Tools::Tool` to support execution handler block/proc and `execute(arguments : Hash(String, JSON::Any)) : String`.
   - Expose `Mantle::Messages::Message` alias.
7. **Release Notes Documentation**: Document breaking changes, rationale, removals, and migration guide in `notes/releases/v1.0.0.md`.

## 3. Verification & Validation (V&V)
* **Verification Plan:**
  - Execute `crystal spec spec/mantle/steps/*` in isolated worktree `.worktrees/mantle-tkt-006-refactor-flow-to-step`.
  - Execute full test suite `crystal spec` to verify clean build and 0 failures.
  - Verify `StepResult` unit specs (ok?, err?, safe unwrap vs raising unwrap, metadata tracking).
  - Verify `Step` unit specs (text response, token streaming &block, multi-step tool loops, max_iterations limit, on_status emissions).
* **Verification Evidence:**
  - `crystal spec spec/mantle/steps/*` executed successfully: 17 examples, 0 failures, 0 errors, 0 pending.
  - Full test suite `crystal spec` executed successfully: 296 examples, 0 failures, 0 errors, 0 pending.
  - `crystal tool format` cleanly formatted all files.
* **Validation Plan:**
  - Verify complete elimination of `Flow` hierarchy and clean top-level namespacing `Mantle::Step`.
  - Verify all documentation and examples in `notes/releases/v1.0.0.md`, `README.md`, and `examples/`.
* **Validation Evidence:**
  - Legacy `src/mantle/flows/` deleted; top-level `Mantle::Step`, `Mantle::StepResult(T, E)`, and `Mantle::StepError` verified.
  - All examples updated to use idiomatic `if reply = result.value` binding with `.unwrap` reserved for test assertions.
  - Release notes in `notes/releases/v1.0.0.md` updated with Section 7.

## Open Questions & Concurrency Concerns
* None. Unparameterized top-level types and pure functional pipeline ensure safe concurrent execution without shared mutable state.

## 4. Outcome & Integration
* **Status**: CLOSED
* **Merged Commits**:
  - `a360f31` refactor(core): replace legacy Flow hierarchy with Mantle::Step and StepResult (TKT-006)
  - `f7a3a13` docs(examples): adopt if reply = result.value pattern instead of unwrap
* **Summary**: Worktree `.worktrees/mantle-tkt-006-refactor-flow-to-step` successfully fast-forward merged to `main`, pruned, and closed.

## 5. Revision History
* 2026-09-08: Ticket created for refactoring Flow into Mantle::Step and StepResult(T, E).
* 2026-09-08: Implementation completed in worktree, all 296 specs verified passing, branch merged to `main`, worktree pruned, ticket closed.
