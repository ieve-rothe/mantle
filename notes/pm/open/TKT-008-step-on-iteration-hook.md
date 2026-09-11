---
ID: TKT-008
Title: Step Per-Iteration Hook for Caller-Owned Working Buffer Projection
Status: Open
Priority: High
---

## 1. User Need

Applications that run long multi-tool turns against small-context models need to observe and reshape the message buffer **while a turn is still executing**, not only before it starts and after it ends.

Today `Mantle::Step#run` is opaque for the duration of a turn. It accepts `messages`, copies them into a private working buffer, accumulates assistant-with-`tool_calls` and `tool` messages across iterations, and returns a final `StepResult`. The caller sees the start state and the end state, and nothing in between.

Three needs follow from that, and none of them are satisfiable from outside:

1. **Context pressure inside a single turn.** Every iteration re-sends the whole accumulated buffer. A debugging turn that runs a build (8 KB of errors), reads three files (4 KB each), and greps (2 KB) has put ~30 KB on the wire by iteration 6 and exhausted an 8k–32k local model's window well before hitting the iteration cap. The caller has no way to shrink that buffer, because the buffer is private. Pruning *history* cannot help — there is no history involved; the growth is entirely within the executing turn.

   The individual messages also cannot be **removed**: every `tool` message must pair with a `tool_call` id in a preceding assistant message, and breaking that pairing produces a history the provider rejects. What a caller needs is to keep each message and its `tool_call_id` while rewriting its `content` down to a short prefix plus a truncation marker — leaving the most recent results intact, since those are the model's active working set.

2. **Faithful turn reconstruction.** A caller that maintains its own conversational record needs the *exact* assistant messages the provider emitted, because tool-call **grouping** is semantically load-bearing: two calls issued in one assistant message is a different history from two issued sequentially, and some providers reject a resynthesized version. Interleaved assistant text ("Let me check the config first…") alongside tool calls is likewise lost. Since `Step` discards its buffer, the caller's only option is to *synthesize* those messages from the tool results it saw in its handlers — a guess that is wrong in exactly the cases that matter.

3. **Mid-turn accounting.** A caller enforcing a per-turn token or cost ceiling, or calibrating a token estimator against real usage, needs `prompt_eval_count` / `eval_count` per iteration. `StepResult#raw_response` carries only the final response, so a 15-iteration turn reports as one data point and cannot be stopped partway.

The immediate consumer is NIGHTMARE (`../nightmare`, see its `docs/ARCHITECTURE.md` §2.1 and Pipeline 3), whose R2 requirement — "when approaching token limits during multi-step tool iterations, truncate older consumed tool results within the active turn while preserving the last 2 verbatim" — is currently unimplementable through `Mantle::Step`. But the need is general to any agent harness against a constrained context window.

## 2. Specification

### 2.1 New optional property on `Mantle::Step`

```crystal
# src/mantle/steps/step.cr

# Optional per-iteration projection hook. Invoked immediately before each
# inference call with the current working buffer and the previous iteration's
# response (nil on the first iteration). Returns the buffer to send.
property on_iteration : Proc(Array(Mantle::Message), Mantle::Clients::Response?, Array(Mantle::Message))?

def initialize(
  @client : Mantle::Clients::Client,
  @tools : Array(Mantle::Tools::Tool) = [] of Mantle::Tools::Tool,
  @max_iterations : Int32 = 10,
  @on_status : Proc(Symbol, Nil)? = nil,
  @tool_callback : Proc(String, Hash(String, JSON::Any), String)? = nil,
  @on_iteration : Proc(Array(Mantle::Message), Mantle::Clients::Response?, Array(Mantle::Message))? = nil,
)
end
```

### 2.2 Invocation point

Inside `#run`, immediately before each `@client.execute` call — after the iteration counter and `max_iterations` check, before inference:

```crystal
if hook = @on_iteration
  working_messages = hook.call(working_messages, last_response)
end
```

`last_response` is the already-tracked local from the previous iteration. It is `nil` on the first iteration.

### 2.3 Contract

- **Default `nil` is identity.** When unset, `#run` behaves exactly as it does today. This is additive; no existing caller changes.
- **The hook's return value is authoritative** for the following inference call and becomes the new `working_messages`. A hook that returns its argument unmodified is a no-op observer.
- **Invoked exactly once per iteration**, including the first, and including iterations entered after tool execution.
- **Not invoked** on the retry-free early-return paths (`max_iterations` exceeded, terminal tool error, malformed output) — those return before the next inference call.
- **Exceptions propagate.** A hook that raises aborts `#run` with that exception rather than converting it to a `StepError`. This is deliberate: it is how a caller implements cooperative cancellation between iterations, and swallowing it would silently continue a turn the caller asked to stop.
- **Pre-flight only.** Never invoked after the final response; see §2.5.
- **`@on_iteration` is never invoked concurrently with itself** within a single `#run` call.

### 2.4 Graph isolation is preserved

TKT-007 established that "Step execution must remain a graph-isolated transform that executes turns and tool loops without mutating the canonical context graph or external storage." This hook does not weaken that:

- `messages`, the caller's input array, remains untouched — `#run` still opens with `working_messages = messages.dup`.
- The hook operates only on `working_messages`, which is already ephemeral and already discarded when `#run` returns.
- `Step` still writes to no store and mutates no `ContextManager` / `ContextStore`.

The invariant is that `Step` does not mutate the caller's *persistent* state. A caller reshaping its own ephemeral projection of that state is the same category of operation as `ContextManager#project_view` — the difference is only that it happens per-iteration instead of once per turn. If anything the hook *strengthens* isolation, by giving callers a sanctioned way to influence in-turn assembly instead of pushing them to reimplement the loop.

### 2.5 Hook is strictly pre-flight

The hook fires only immediately before an inference call. It does **not** fire after the final response: the loop exits at that point, so anything it returned would be discarded, and firing it would break the "this is the buffer about to be sent" contract that makes the return value meaningful.

Callers accumulating per-turn spend therefore read the final iteration's usage from `StepResult#raw_response.eval_count` and add it to whatever they accumulated across hook invocations. Document this in the property's doc comment so the asymmetry is expected rather than surprising.

### 2.6 Required doc comment: prefer `#map` over index mutation

`Mantle::Message` is a `struct`, so `messages.last.content = "new"` mutates a copy and the write is lost — the sharpest Crystal trap for anyone arriving from Ruby. Because this hook makes message rewriting a sanctioned pattern, the property's doc comment must steer callers to a rebuild rather than in-place mutation:

```crystal
# Safe: build a new array; each element is a fresh struct.
working_messages.map do |msg|
  if msg.role == "tool" && should_shed?(msg)
    Mantle::Message.new("tool", "[truncated]", tool_call_id: msg.tool_call_id)
  else
    msg
  end
end
```

Note `tool_call_id:` is passed by **keyword**. The third positional parameter of `Message#initialize` is `tool_calls`, not `tool_call_id`; passing it positionally type-errors, or worse would silently populate the wrong field if the types ever converged. Worth calling out in the comment, since dropping `tool_call_id` is exactly what breaks pair integrity.

Index write-back (`msgs[i] = mutated`) remains correct and is still covered by the §3 spec, but `#map` is the recommended form: it makes the copy semantics explicit instead of relying on the caller remembering to assign back.

### 2.7 Non-goals for this ticket

- **No post-response hook.** Resolved as out of contract; see §2.5.
- **No `on_error` hook.** A provider length rejection (HTTP 400, `context_length_exceeded`) still propagates out of `#run`, so a caller recovers by shedding and re-running the turn, not by retrying the single failed inference call in place. Accepted as a known gap; it is a reactive backstop, not a hot path. A follow-on ticket if it proves to fire in practice.
- **No abort/cancellation primitive on `Client#execute`.** Cancellation remains cooperative: raise from the `on_chunk` block (mid-stream) or from `on_iteration` (between iterations). A stream that has stopped producing chunks still cannot be interrupted until it times out. Separate concern.
- **No reasoning-block channel on `Mantle::Message`.** `Message` has no field for provider-native thinking blocks or signatures, which matters for providers that require verbatim echo of reasoning during tool use. Out of scope here; noted in §Open Questions.
- **No change to `Mantle::Session`.** `Session#run_turn` gains nothing and loses nothing; it may pass the hook through later if a need appears.

## 3. Verification & Validation (V&V)

* **Verification Plan:**
  1. `crystal spec` — full suite green, no regressions against the current 301-example baseline.
  2. `crystal tool format --check` — clean.
  3. New specs in `spec/steps/step_spec.cr`:
     - **Default nil is inert.** An existing multi-iteration tool-loop spec produces a byte-identical request sequence with `on_iteration` unset. Assert against a recording fake client.
     - **Invocation count and ordering.** A 3-iteration turn invokes the hook exactly 3 times, each immediately before an inference call.
     - **First-iteration `last_response` is nil**; iteration N receives iteration N−1's `Mantle::Clients::Response` with the expected `prompt_eval_count`.
     - **Return value is authoritative.** A hook that rewrites a `tool` message's `content` causes the *next* request to carry the rewritten content; a hook that appends a message causes it to appear; a hook returning its input unchanged is a no-op.
     - **Struct write-back.** A hook rewriting `msgs[i]` by index must be observable in the next request. (`Mantle::Message` is a `struct` — `msgs[i].content = x` mutates a copy and silently no-ops. Pins the semantics for callers.)
     - **`#map` rebuild.** The §2.6 recommended form produces the expected next request, with `tool_call_id` preserved on rebuilt tool messages.
     - **Not invoked post-response.** A 3-iteration turn invokes the hook 3 times, not 4; the last invocation precedes the final inference call.
     - **Pair integrity survives rewriting.** After a hook truncates tool-message content, every `tool_call_id` still pairs with a preceding assistant `tool_call`.
     - **Exceptions propagate** as the raised exception, not as `StepError`.
     - **Input immutability.** The caller's `messages` array is unmodified after a `#run` whose hook mutated and appended heavily.
  4. `crystal build --no-codegen` clean across `examples/`.
* **Verification Evidence:** _pending_
* **Validation Plan:**
  1. Implement NIGHTMARE's `Harness::ToolLoop#on_iteration` against the hook and confirm its invariant tests T1–T4, T11, and T17 pass (see `../nightmare/docs/ARCHITECTURE.md` §9): no orphaned pairs after any shed sequence; shed→rebuild byte-identical for unchanged history; write-back effective; last-2-verbatim honoured; token divisor converging from real `prompt_eval_count`.
  2. Drive a real multi-iteration turn against a local Ollama model with a deliberately small `num_ctx`, on a task that would overflow without shedding (build failure → read three files → grep → rebuild). Confirm the turn completes rather than erroring on context length.
  3. Confirm NIGHTMARE's turn record reproduces provider assistant messages verbatim, including a multi-call assistant message and one with interleaved content — i.e. the grouping problem is actually solved and not merely worked around.
* **Validation Evidence:** _pending_

## Open Questions & Concurrency Concerns

* ~~**Hook signature shape.**~~ **RESOLVED 2026-09-11: two args, no context struct.** `(Array(Message), Response?) -> Array(Message)` is the boundary. A mutable context struct would encourage hidden state mutation; passing the array in and out forces the caller to explicitly return new state, preserving functional purity. `Proc` arity is cheap to widen later if a third argument (e.g. a step execution ID) is ever needed.
* ~~**Should the hook also fire after the final response?**~~ **RESOLVED 2026-09-11: no.** The contract is strictly pre-flight — projection for the *next* inference call. Firing after the final response would violate it, since the return value would be discarded as the loop exits. Callers accumulate the final iteration's spend from `StepResult#raw_response.eval_count`. Keep the hook bound to the inference trigger. See §2.3.
* ~~**`Mantle::Message` is a `struct`.**~~ **RESOLVED 2026-09-11: document `#map`, spec the write-back.** Guidance is in §2.6; the write-back spec stays in §3. Whether `Message` should become a class remains open — out of scope here, but it would eliminate the bug class entirely rather than documenting around it.
* **Performance.** One `Proc` call per iteration against `nil`-checked dispatch: negligible. The real cost is whatever the caller does inside, which is the caller's budget. No new allocation when the hook is unset.
* **Concurrency.** No new shared state; the hook is called on the same fiber as `#run`, synchronously, between inference calls. Callers must not block the fiber indefinitely inside the hook — worth a doc note, since a caller tempted to prompt the user from inside the hook would stall the turn.
* **Reasoning blocks (adjacent, not blocking).** `Mantle::Message` has no field for provider-native thinking blocks with signatures. Not a live problem: Mantle ships only `OllamaClient`, and the requesting consumer has since scoped itself to Ollama local inference only (NIGHTMARE decision D2). It becomes live the moment an Anthropic-style client is added, since those providers require reasoning blocks echoed back verbatim when continuing tool use within a turn — and this hook would be the natural place a caller preserves them. Noted only so the two designs stay compatible; **no scaffolding should be built for it in this ticket.** Separate ticket when such a client lands.

## 4. Revision History
* 2026-09-11: Open questions resolved by owner — two-arg signature confirmed (no context struct, preserves functional purity); hook is pre-flight only (no post-response fire; callers read `StepResult#raw_response.eval_count`); `#map` rebuild documented as the recommended form over index write-back. §2.5 and §2.6 added. `Message` struct-vs-class remains open as a separate concern.
* 2026-09-11: Ticket opened. Need surfaced while revising NIGHTMARE's architecture (Revision 2) — its R2 in-turn shedding requirement is unimplementable through the current `Step#run`. Research: read `Step#run` control flow, confirmed `working_messages` is local and discarded; confirmed `Message` is a `struct` with silent copy-mutation semantics (verified experimentally); confirmed no abort hook exists on `Client#execute`; confirmed `Response` exposes `prompt_eval_count` / `eval_count` per call. Considered and rejected the alternative of NIGHTMARE reimplementing the tool loop over `Client#execute` directly — it duplicates ~100 lines of Mantle's error taxonomy and tool dispatch, diverges over time, and abandons the framework's step contract for its primary code path. Decided in favour of the additive hook, recorded as NIGHTMARE architecture decision D1.
