---
ID: TKT-001
Title: Remove Obsolete Logger Infrastructure
Status: Closed
Priority: High
---

## 1. User Need
Developers maintaining and extending Mantle need a clean, minimal codebase where each file earns its place. The current logger subsystem (`app_logger.cr` defining a namespace, `logger.cr` providing `Logger`/`FileLogger`/`DetailedLogger`) adds mental overhead without proportional value — `app_logger.cr` is just a one-liner that still requires consumer setup, and `logger.cr`'s per-turn logging has been superseded by the structured JSONL receipts in `LoggingClient`. Removing these and documenting the intended logging approach reduces confusion for contributors.

## 2. Specification
1. **Delete** `src/mantle/support/app_logger.cr` and `src/mantle/support/logger.cr`
2. **Inline** `Log = ::Log.for("mantle")` into `Mantle` module in `mantle.cr`
3. **Remove** the `logger` parameter from all Flow constructors (`Flow`, `ChatFlow`, `ToolEnabledChatFlow`)
4. **Remove** all `@logger.log_message(...)` and `@logger.log_api_payloads(...)` calls from `flow.cr`
5. **Remove** `require "../support/app_logger"` from `context_store.cr`, `memory_store.cr`, `context_manager.cr`, `client.cr`
6. **Update** `logging_client.cr` references from `Mantle::Support::Log` to `Mantle::Log`
7. **Delete** `spec/app_logger_spec.cr` and `examples/logger_test.cr`
8. **Remove** `DummyLogger` from `spec/spec_helper.cr` and all test files
9. **Update** `ARCHITECTURE.md` and `CLAUDE.md`: remove Logger sections, add Application Logging documentation
10. **Ensure** all Mantle specs pass

## 3. Verification & Validation (V&V)
* **Verification Plan:**
  - Run `crystal spec` in mantle/ — all specs must pass
  - Grep for residual references to `Mantle::Support::Logger`, `FileLogger`, `DetailedLogger`, `DummyLogger` — must return zero hits in mantle source
  - Confirm `Mantle::Log` resolves from storage and client modules
  - Confirm `LoggingClient` spec passes unchanged
* **Verification Evidence:**
  - `crystal spec` executed successfully: 290 examples, 0 failures, 0 errors.
  - Residual grep search for `Mantle::Support::Logger`, `FileLogger`, `DetailedLogger`, `DummyLogger` returned 0 hits in mantle source and specs.
  - `LoggingClient` specs pass without issues.
* **Validation Plan:**
  - Review updated ARCHITECTURE.md and CLAUDE.md for clear, actionable logging setup guidance
  - Confirm empaws can still compile (may need separate empaws-side ticket for migration)
* **Validation Evidence:**
  - ARCHITECTURE.md and CLAUDE.md updated with clear Crystal standard `Log` usage examples (`Mantle::Log = ::Log.for("mantle")`).
  - Started `notes/releases/v1.0.0.md` release notes for baseline v1.0.0 migration tracking.

## Open Questions & Concurrency Concerns
* Empaws-side migration (`Empaws::AppLogger`, `dependency_builder.cr`, etc.) will be handled in a separate ticket.

## 4. Revision History
* 2026-09-08: Ticket created. Scope defined: remove app_logger.cr, logger.cr, update flows, tests, and docs.
* 2026-09-08: Ticket completed and closed. Verified 290 passing specs and clean grep across mantle.
