# Architecture Design Note: Context Assembly, Ephemeral Injections, and Memory Pipeline

## Overview

In Mantle v1.0.0, the prompt compilation and inference pipeline is strictly decoupled from state persistence and storage mutation.

The conversation state graph (`ContextStore` / `ContextManager`) stores only **canonical history** (permanent user turns, assistant responses, and tool execution outputs). Transient instructions, daemon triggers, environment metadata, and formatting reminders are modeled explicitly as **Ephemeral Injections**. They are injected deterministically into the prompt window during view projection (`ContextManager#project_view`) and recorded in the JSONL audit receipt (`ReceiptWriter`), but **never** persisted to the canonical graph.

---

## 1. Deterministic Spatial Projection Pipeline

When assembling the prompt window for an LLM turn, `ContextManager#project_view` compiles messages in a strictly deterministic spatial order:

```text
[Base System Prompt]
         │
         ▼
[System Injections]        (e.g., identity nudges, environmental rules, runtime constraints)
         │
         ▼
[Long-Term Memory View]    (Layered memory summary / demon outputs / consolidated knowledge)
         │
         ▼
[Pre-History Injections]   (e.g., active frame/topic context, session status, workspace info)
         │
         ▼
[Conversation History]     (Canonical User, Assistant, and Tool turns from ContextStore)
         │
         ▼
[Tail Injections]          (e.g., formatting reminders, dev mode triggers, immediate signals)
```

### Zone Definitions & Responsibilities

| Spatial Zone | Role | Purpose & Examples |
| :--- | :--- | :--- |
| **Base System Prompt** | `system` | Core behavioral instructions and persona defined on the `ContextStore`. |
| **System Injections** | `system` | Transient system instructions, active security rules, temporal timestamps, or runtime flags. |
| **Long-Term Memory View** | `system` | Consolidated summaries from `JSONLayeredMemoryStore` representing conversation history that was rolled over from context. |
| **Pre-History Injections** | `system` | Topic context, current frame identification, or daemon status that orients the conversation before user history begins. |
| **Conversation History** | `user`, `assistant`, `tool` | The active sliding window or graph branch of canonical turns from `ContextStore`. System messages stored in the context store are excluded to avoid duplication with the base prompt. |
| **Tail Injections** | `system` | Immediate guidance appended at the absolute end of the prompt window (e.g. "Answer concisely in JSON", dev mode switch triggers, frame-switch interrupts). |

---

## 2. Long-Term Memory (LTM) Consolidation

Mantle employs a dual-tier memory model:

1. **Short-Term Context Store (`ContextStore`)**:
   - Maintains recent turns up to configurable token thresholds (`token_target`, `token_softmax`, `token_hardmax`).
   - Supports atomic persistence (`JSONContextStore`) and ephemeral sliding window (`EphemeralSlidingContextStore`).
2. **Layered Memory Store (`JSONLayeredMemoryStore`)**:
   - Ingests pruned conversation blocks when context reaches `token_hardmax`.
   - Organizes memory into discrete cascade layers using background summarizers (`Squishifiers`).

During `ContextManager#project_view`, the current aggregated view of the layered memory store (`memory_store.current_view`) is fetched and positioned immediately following system injections and prior to pre-history injections.

---

## 3. Graph-Isolated Step Execution

`Mantle::Step` is a dumb execution transform:

```text
[projected_view : Array(Message)]
              │
              ▼
       [Step#run(view)]
              │
    ┌─────────┴─────────┐
    ▼                   ▼
[Success]            [Failure]
    │                   │
    ▼                   ▼
Commit Assistant     Do NOT mutate graph;
Turn to Context      Route error to caller
```

- **Immutability**: `Step#run` duplicates the input messages (`working_messages = messages.dup`).
- **Tool Loops**: Tool calls and their execution results are appended exclusively to the local `working_messages` buffer during the loop. They never leak or mutate the caller's message slice.
- **Outcome Purity**: Only the final resolution is returned via `Mantle::StepResult(String, StepError)`.

---

## 4. Session Orchestrator & Idempotency Contract

`Mantle::Session` coordinates the end-to-end turn lifecycle:

```text
[Incoming Trigger / Queue Item]
             │
             ▼
   [Check Idempotency] ────────┐
   (If Retry: skip commit)     │
             │                 │ (Already committed)
             ▼                 ▼
   [Commit Trigger to Graph] ──┘
             │
             ▼
   [Project Context View]  (+ System, Pre-History, Tail Injections)
             │
             ▼
     [Step#run(view)]      (Graph-Isolated Transform)
             │
             ├──► [On Success]: Commit Assistant output to ContextGraph
             │                  Emit Success Receipt to ReceiptWriter
             │
             └──► [On Failure]: Do NOT corrupt context with partial turns
                                Emit Failure Receipt to ReceiptWriter
                                If Retryable: queue consumer can re-execute safely
```

### Error Taxonomy
* **Retryable (`err.retryable?`)**: `ClientFailure` (network drop, timeout), `RateLimited` (HTTP 429).
* **Terminal (`err.terminal?`)**: `MalformedOutput`, `MaxIterationsReached`, `ToolExecutionFailure`.

### Idempotency Guarantee
When a turn encounters a `Retryable` error, the triggering message has already been committed to the canonical graph. When the queue consumer retries the turn (`is_retry: true`), `Session#run_turn` checks if the trigger was already recorded and skips appending it a second time. This prevents duplicated user prompts or event triggers.

---

## 5. Audit Trail in JSONL Receipts

Every turn logged by `LoggingClient` or `Session` captures the full deterministic state in `ReceiptWriter`:

```json
{
  "id": "c6a282f1-61b6-4b6c-843e-a1fb923ce75d",
  "sequence_id": "seq-456",
  "timestamp": "2026-09-08T15:30:00.000Z",
  "model": "gpt-oss:20b",
  "input_hash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "prompt": [ ... ],
  "ephemeral_injections": {
    "system": [
      { "role": "system", "content": "Environment: sandbox" }
    ],
    "pre_history": [
      { "role": "system", "content": "Active Frame: Development" }
    ],
    "tail": [
      { "role": "system", "content": "Respond strictly in JSON" }
    ],
    "memory_view": "[Memory Layer 0] Previous discussion on architecture..."
  },
  "raw_output": {
    "content": "{\"status\":\"ok\"}",
    "thinking": null,
    "tool_calls": null,
    "done_reason": "stop",
    "prompt_eval_count": 120,
    "eval_count": 14
  },
  "latency_ms": 342,
  "status": "success",
  "error_message": null
}
```

This ensures complete offline determinism and auditing: developers can reconstruct the exact prompt window including all ephemeral injections and memory summaries present during inference.
