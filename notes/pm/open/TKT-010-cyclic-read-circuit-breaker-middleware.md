---
ID: TKT-010
Title: Cyclic Read Loop Circuit Breaker Middleware
Status: Open
Priority: High
---

## 1. User Need
Local language models operating within strict token limits (~10k tokens with sliding context stores) frequently fall victim to context amnesia. When an agent attempts to inspect or explore a codebase, earlier file reads are dropped from active context to make room for newer ones. Because the model no longer sees the contents of previously read files, it re-reads them, getting stuck in an infinite exploratory loop (e.g. `read_file(A) -> read_file(B) -> read_file(C) -> read_file(A)`).

Existing loop detection approaches either only check for consecutive identical calls (which misses multi-file cycles) or enforce blunt session-wide counters that falsely flag healthy repetitive development cycles (such as iterative edit-compile-test loops). Developers and harnesses need an intelligent middleware circuit breaker in MANTLE that halts cyclic unmutated inspection thrashing without interfering with legitimate iterative coding workflows.

## 2. Specification
Implement a composable tool middleware: `Mantle::Tools::Middleware::CyclicReadBreaker < Mantle::Tools::Middleware::Base`.

### 2.1 Tool Classification & Configuration
* **Inspection Tools:** Configurable set of read-only/inspection tool names (`inspection_tools : Set(String)`). Defaults to `["read_file", "list_directory", "list_files", "search_files", "search", "file_info"]`.
* **Mutation Tools:** Configurable set of workspace-modifying tool names (`mutation_tools : Set(String)`). Defaults to `["write_file", "replace_in_file", "delete_file"]`.
* **Threshold:** The number of times the exact same inspection call `(tool_name, args_json)` can be executed without an intervening workspace mutation before tripping (default: `3`).
* **Sliding Window:** Optional window size limit (`window_size : Int32?`, e.g. 20 calls) to ensure stale calls from long ago don't penalize long-running sessions, while catching dense clusters of thrashing.
* **Trip Behavior:** 
  * Soft Refusal Mode (default: `raise_on_trip = false`): Returns a structured JSON error string to the model explaining the refusal:
    `{"error": "ERR_CYCLIC_READ: Inspection tool '#{tool_name}' called #{count} times with identical arguments without any intervening workspace mutation. Contents were previously provided. Cease re-reading and take concrete action or write a plan.", "refused": true}`.
  * Terminal Error Mode (`raise_on_trip = true`): Raises `Mantle::Tools::TerminalToolError` with the message if caller wants a hard loop abort.

### 2.2 Invalidation & State Management
* **`record_mutation`:** Public method that clears all accumulated inspection counts and the call history buffer. Automatically called when any tool in `mutation_tools` is executed. Can also be called externally by the host application (e.g. when executing mutating shell commands or user turns).
* **`reset`:** Clears all tracking state.
* **Exemption:** Calls to tools not in `inspection_tools` (such as shell commands or compilation tools) do not increment inspection counters.

## 3. Verification & Validation (V&V)

* **Verification Plan:**
  - Create unit specs in `spec/mantle/tools/middleware/cyclic_read_breaker_spec.cr`.
  - Verify that sequential calls to diverse files pass through without tripping.
  - Verify that repeating the exact same inspection call 3 times trips the breaker with the expected soft refusal message.
  - Verify that invoking a mutation tool (e.g. `write_file`) or calling `.record_mutation` resets the counter and allows subsequent reads of the file without tripping.
  - Verify that setting `raise_on_trip = true` raises `Mantle::Tools::TerminalToolError`.
  - Verify that `window_size` correctly evicts older calls outside the window.
  - Run full suite: `crystal spec`.

* **Verification Evidence:**
  - `crystal spec spec/mantle/tools/cyclic_read_breaker_spec.cr`: 8 examples, 0 failures, 0 errors.
  - `crystal spec`: Full test suite passed (309 examples, 0 failures, 0 errors).

* **Validation Plan:**
  - Verify that wrapping built-in tools (`Builtin.all`) with `CyclicReadBreaker` prevents cyclic file re-reads while allowing typical edit-test iterations.

* **Validation Evidence:**
  - Pending verification.

## Open Questions & Concurrency Concerns
* **Concurrency:** In multi-threaded or multi-fiber agent runners, `@inspection_history` and `@call_log` modifications should be fiber-safe. In Crystal's cooperative concurrency / event loop, operations within standard middleware wrappers do not context-switch mid-hash write unless fibers explicitly yield.
* **Subagents:** Each subagent or step execution pipeline should instantiate its own middleware instance to prevent cross-agent tracking pollution.

## 4. Revision History
* 2026-09-25: Created ticket and implementation plan (TKT-010).
---
