# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mantle is a Crystal framework for abstracting LLM interactions into composable Flow objects. It provides a low-level base layer for building LLM applications with a focus on separation of concerns: implementation details about _how_ to talk to models and structure loops belong in Mantle, while application-specific logic about _what_ an agent should achieve lives in the application layer.

## Development Commands

### Testing
```bash
# Run all tests
crystal spec

# Run specific test file
crystal spec spec/context_store_spec.cr
crystal spec spec/client_spec.cr

# Run a specific test by line number
crystal spec spec/context_store_spec.cr:96
```

### Building and Running
```bash
# Build the project
shards build

# Install dependencies
shards install

# Run example applications
crystal run examples/basic_app.cr
crystal run examples/logger_test.cr
```

### Type Checking
Crystal is statically typed and performs type checking during compilation. Type errors will appear when running `crystal spec` or `crystal run`.

## Architecture

### Core Components

**Flow** (`src/mantle/flow.cr`)
- Base abstraction for LLM inference operations
- Represents self-contained blocks of work (planning, reflection, tool execution, etc.)
- `Flow` is an abstract base class; `ChatFlow` is the concrete implementation
- Each flow has a `run(input, on_response)` method that assembles context, sends to client, and handles response
- Flows coordinate between: context store (manages conversation), client (API communication), and logger (output tracking)

**Client** (`src/mantle/client.cr`)
- Abstract `Client` class defines the contract for LLM API interactions
- `LlamaClient` is the concrete implementation for Ollama-compatible APIs
- Configured via `ModelConfig` record with model name, streaming, temperature, top_p, max_tokens, and API URL
- Returns string responses from `execute(prompt)` method

**ContextStore** (`src/mantle/context_store.cr`)
- Manages ongoing conversation context (not identity or long-term memory)
- Multiple implementations with different retention strategies:
  - `EphemeralContextStore`: Keeps all messages indefinitely
  - `EphemeralSlidingContextStore`: Maintains fixed number of recent messages in memory
  - `JSONSlidingContextStore`: Persists sliding window to JSON file for cross-session continuity
  - `LayeredContextStore`: Stub for future hierarchical context management
- All stores provide `add_message(label, message)` and `chat_context` getter
- `JSONSlidingContextStore` includes `prune(num)` method to manually remove oldest messages

**Logger** (`src/mantle/logger.cr`)
- Abstract `Logger` class for pluggable logging implementations
- `FileLogger`: Writes formatted timestamped entries to file with ASCII dividers
- `DetailedLogger`: Extends FileLogger to write context, user messages, and bot messages to separate files
- Use `DummyLogger` pattern (implement abstract methods as no-ops) for unit tests

**MemoryStore** (`src/mantle/memory_store.cr`)
- `JSONLayeredMemoryStore`: Hierarchical long-term memory with automatic consolidation
- Manages memory in layers: Layer 0 (recent summaries) → Layer 1 (older summaries) → Layer 2, etc.
- Messages from context are squishified and added to Layer 0
- When a layer reaches capacity, oldest messages consolidate to the next layer
- Configuration: `layer_capacity` (max items per layer), `layer_target` (items remaining after consolidation)
- `ingest_step_size = layer_capacity - layer_target` determines batch size for consolidation
- Persists to JSON with `ingest_pending` (messages awaiting squishification) and `layers` arrays
- Fault-tolerant: If squishifier fails, messages remain in `ingest_pending` for retry

### Design Patterns

- **Abstract classes for contracts**: Client and Logger use abstract base classes to enable testing with dummy implementations
- **Record types for configuration**: `ModelConfig` uses Crystal's `record` macro for immutable configuration objects
- **Composition over inheritance**: Flow composes context store, client, and logger rather than inheriting functionality
- **Separation of concerns**: Context (short-term), memory (long-term), and identity are distinct concepts

### File Organization

```
src/mantle/
├── flow.cr           # Flow abstractions and ChatFlow implementation
├── client.cr         # LLM client abstractions and Ollama implementation
├── context_store.cr  # Context management with multiple strategies
├── logger.cr         # Logging abstractions and file-based implementations
└── memory_store.cr   # Future: long-term memory (currently stubs)

spec/
├── context_store_spec.cr  # Comprehensive context store tests
├── client_spec.cr         # Client tests
└── mantle_spec.cr        # Main library tests

examples/
├── basic_app.cr      # Basic usage example
└── logger_test.cr    # Logger demonstration
```

## Testing Conventions

- Tests use Crystal's built-in Spec framework
- Arrange-Act-Assert pattern with clear comments
- Context stores tested with temporary files in `/tmp/` (always cleaned up)
- File-based tests use `Time.utc.to_unix_ms` and `Random.rand` for unique filenames
- Dummy implementations (DummyContextStore, DummyLogger) for isolating components

## Implementation Lessons Learned

### Recursive Consolidation in JSONLayeredMemoryStore

The layered memory consolidation uses recursive `cascade()` calls to move summaries between layers. Key design decisions:

**Capacity Check Timing**
- Check capacity BEFORE adding to prevent filling beyond capacity
- Additional check AFTER processing ingest_pending ensures Layer 0 consolidates when full
- Do NOT add post-processing checks to recursive calls (prevents infinite cascade chains)

**Consolidation Flow**
- `ingest()` adds messages to `@ingest_pending`, then calls `cascade(-1)`
- `cascade(-1)` squishifies all pending messages and adds each to Layer 0
- When Layer 0 reaches capacity during cascade, recursively calls `cascade(0)`
- `cascade(0)` batches `ingest_step_size` items from Layer 0, squishifies, adds to Layer 1
- This continues recursively up the layer hierarchy as needed

**Preventing Infinite Recursion**
- Safety limit: max layer index of 50 (reasonable for any realistic usage)
- The layer index itself serves as recursion depth
- Final consolidation check only for layer -1 (entry point), not for recursive calls

**Realistic Parameters**
- Recommended: `layer_capacity: 7-10`, `layer_target: 5`
- Avoid very small values like `capacity: 2, target: 1` (creates excessive layers)
- With realistic parameters, deep cascading requires significant message volume

**Test Design**
- Tests with unrealistic parameters revealed edge cases but were harder to reason about
- Deterministic squishifier in tests preserves message content in summaries
- When testing consolidation, check specific layer sections, not entire view

## API Design Notes

- Clients and Loggers are abstract to support testing and alternative implementations
- Context stores handle message formatting with `[Label] message\n` pattern
- The `on_response` callback in Flow.run allows streaming or custom response handling
- JSONSlidingContextStore automatically persists after each message for crash resilience
- JSONLayeredMemoryStore: `layer_capacity` must be greater than `layer_target` (validated on initialization)
