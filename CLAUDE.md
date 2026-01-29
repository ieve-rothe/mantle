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
- Stub for future long-term memory management (distinct from context)
- `MemoryCoordinator` and `LayeredMemoryStore` classes are placeholders

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

## API Design Notes

- Clients and Loggers are abstract to support testing and alternative implementations
- Context stores handle message formatting with `[Label] message\n` pattern
- The `on_response` callback in Flow.run allows streaming or custom response handling
- JSONSlidingContextStore automatically persists after each message for crash resilience
