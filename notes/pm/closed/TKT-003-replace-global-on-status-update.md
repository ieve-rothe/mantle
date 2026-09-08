---
ID: TKT-003
Title: Replace Global Mantle.on_status_update Singleton
Status: Closed
Priority: High
---

## 1. User Need
As a developer integrating Mantle, I need status updates to be handled without shared global state so that multiple flow instances and threads can operate concurrently with isolated status handlers, and unnecessary stdlib dependencies like `set` are eliminated.

## 2. Specification
* Delete `mantle/support/status.cr` and eliminate `class_property on_status_update` singleton and `require "set"`.
* Add `on_status : Proc(Symbol, Nil)?` property to `Flow` and `ContextManager` for instance-level status callback registration via `initialize` or property accessor.
* `Flow#run` signatures remain untouched (no call-level parameter).
* `ContextStore` and `MemoryStore` will not emit UI status callbacks. Replace `:new_context_file` emissions with standard logging.
* Dispatch flow status flags (`:idle`, `:tool_loop`) via `Flow#on_status` and context management flags (`:context_softmax_exceeded`, `:memory_consolidation`) via `ContextManager#on_status`.

## 3. Verification & Validation (V&V)
* **Verification Plan:** Run `crystal spec` in `mantle/` verifying all flow and context tests pass, and write new specs in `spec/mantle/status_instance_spec.cr` verifying instance-level status callbacks.
* **Verification Evidence:** Executed `crystal spec` in `mantle` — 281 examples, 0 failures, 0 errors. Verified `status_instance_spec.cr` test suite passing.
* **Validation Plan:** Verify no references to `require "set"` or `Mantle.on_status_update` remain in the codebase and downstream `salamander` specs pass cleanly.
* **Validation Evidence:** Removed `src/mantle/support/status.cr` and `require "set"`. Confirmed zero static status singleton references remain. Executed `crystal spec` in `salamander` — 14 examples, 0 failures, 0 errors.

## Open Questions & Concurrency Concerns
* None. Instance-level callbacks ensure clean scoping per flow/manager without shared global state.

## 4. Revision History
* 2026-09-08: Created ticket TKT-003 for global status update refactoring.
* 2026-09-08: Completed implementation and closed ticket.
