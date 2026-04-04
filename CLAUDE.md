# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Mantle is a Crystal framework for abstracting LLM interactions into composable Flow objects. It provides a low-level base layer for building LLM applications with a focus on separation of concerns: implementation details about _how_ to talk to models and structure loops belong in Mantle, while application-specific logic about _what_ an agent should achieve lives in the application layer.

**For detailed architecture**, see `ARCHITECTURE.md`
**For tool calling interfaces**, see `TOOL_CALLING_IMPLEMENTATION.md`

---

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
crystal run examples/tool_calling_app.cr
```

### Type Checking
Crystal is statically typed and performs type checking during compilation. Type errors will appear when running `crystal spec` or `crystal run`.

---

## Coding Standards

### Design Patterns

**Abstract Classes for Contracts**
- Use abstract base classes to define interfaces (e.g., `Client`, `Logger`)
- Enables testing with dummy implementations
- Example: `DummyClient`, `DummyLogger` in specs

**Record Types for Configuration**
- Use Crystal's `record` macro for immutable configuration objects
- Example: `ModelConfig` with positional arguments
- Keeps configuration simple and type-safe

**Composition Over Inheritance**
- Flow composes `context_manager`, `client`, and `logger` rather than inheriting
- Components can be swapped independently
- Easier to test in isolation

**Separation of Concerns**
- **Context** (short-term): Managed by `ContextStore`
- **Memory** (long-term): Managed by `MemoryStore`
- **Identity**: Future feature (system prompts, personality)
- Keep these distinct in design and implementation

### Testing Conventions

**Test Framework**
- Use Crystal's built-in Spec framework
- Follow Arrange-Act-Assert pattern with clear comments
- Use descriptive test names that explain what's being tested

**Temporary Files**
- Context stores tested with temporary files in `/tmp/`
- Always clean up in `after_all` blocks
- Use `Time.utc.to_unix_ms` and `Random.rand` for unique filenames
- Example: `/tmp/test_#{Time.utc.to_unix_ms}_#{Random.rand(10000)}.txt`

**Dummy Implementations**
- Create dummy classes for testing (`DummyContextStore`, `DummyLogger`, `DummyClient`)
- Implement abstract methods as no-ops or simple returns
- Isolates components for focused unit testing

**Test Organization**
- One spec file per source file (e.g., `client_spec.cr` for `client.cr`)
- Use `describe` and `it` blocks to organize tests hierarchically
- Test both success and failure cases

---

## API Design Guidelines

### Client Interface
- Abstract `Client` class defines contract for LLM API interactions
- Returns `Response` objects (contains optional `content` and `tool_calls`)
- Tool parameter is optional: `execute(messages, tools : Array(Tool)? = nil)`
- Enables testing and alternative implementations

### Flow Interface
- Base `Flow` class coordinates context, client, and logger
- `ChatFlow` for basic interactions (extracts text from Response)
- `ToolEnabledChatFlow` for tool calling (handles loop automatically)
- Use `on_response` callback pattern for streaming or custom handling

### Context Store Interface
- All stores provide `add_message(label, message)` and `current_view`
- Message format: `{"role" => "user|assistant|system", "content" => "..."}`
- Handle message formatting internally (don't expose raw storage format)

### Logger Interface
- Abstract `Logger` class for pluggable implementations
- `log_message(label, message, context)` is the primary method
- Use `DummyLogger` pattern for tests (no-ops)

### Tool Interfaces
- Tool definitions use `JSON::Serializable` for API compatibility
- Built-in tools return JSON: `{"success": true, "content": "..."}` or `{"error": "..."}`
- Custom tools use callback signature: `(String, Hash(String, JSON::Any)) -> String`
- Keep tool logic in application layer, framework only provides mechanism

---

## Best Practices

### Error Handling
- Use exceptions for unrecoverable errors
- Return error objects/messages for recoverable failures
- Tool execution errors return JSON error format
- Don't let one tool failure stop remaining tools

### Safety
- **Path Validation**: Built-in tools validate all filesystem access
- **Iteration Limits**: Tool calling loops enforce `max_iterations` to prevent infinite loops
- **Configuration**: Use explicit configuration objects (`BuiltinToolConfig`, `ModelConfig`)

### Natural Language in Context
- Tool interactions stored as natural language, not raw JSON
- Makes context human-readable and LLM-friendly
- Example: "Called read_file(file_path: 'test.txt'). Result: Hello, World!"
- Helps with memory consolidation (squishification)

### JSON Format Conventions
- Use `JSON::Serializable` for structs that need serialization
- Use `@[JSON::Field(emit_null: false)]` to omit nil fields
- Return JSON strings from tool callbacks, not raw objects

### Memory Management
- Keep context (short-term) and memory (long-term) separate
- Use squishifiers to summarize old messages before moving to memory
- Configure `layer_capacity` > `layer_target` in `JSONLayeredMemoryStore`
- Recommended: `layer_capacity: 7-10`, `layer_target: 5`

---

## Common Patterns

### Creating a Basic Flow
```crystal
# Setup components
context_store = Mantle::EphemeralSlidingContextStore.new(system_prompt, 50)
memory_store = Mantle::JSONLayeredMemoryStore.new(...)
context_manager = Mantle::ContextManager.new(context_store, memory_store, "User", "Bot")
client = Mantle::LlamaClient.new(model_config)
logger = Mantle::FileLogger.new("/tmp/log.txt", "User", "Bot")

# Create flow
flow = Mantle::ChatFlow.new(context_manager, client, logger)

# Run
flow.run("Hello!", ->(response : String) { puts response })
```

### Using Tool Calling
```crystal
# Use ToolEnabledChatFlow instead
flow = Mantle::ToolEnabledChatFlow.new(context_manager, client, logger)

# With built-in tools
flow.run(
  "List files",
  builtins: [Mantle::BuiltinTool::ReadFile, Mantle::BuiltinTool::ListDirectory],
  builtin_config: Mantle::BuiltinToolConfig.new(Dir.current),
  on_response: ->(r : String) { puts r }
)

# With custom tools
flow.run(
  "What time is it?",
  custom_tools: [time_tool],
  tool_callback: my_callback,
  on_response: ->(r : String) { puts r }
)
```

### Testing with Dummy Implementations
```crystal
# Create dummy components
context_store = DummyContextStore.new
context_manager = DummyContextManager.new(context_store)
client = DummyClient.new  # Returns Response.new(content: "Simulated", tool_calls: nil)
logger = DummyLogger.new

# Test flow in isolation
flow = Mantle::ChatFlow.new(context_manager, client, logger)
```

---

## File Organization

Quick reference for finding code:

```
src/mantle/
├── flow.cr              # Flow, ChatFlow, ToolEnabledChatFlow
├── client.cr            # Client, LlamaClient, Response types
├── tools.cr             # Tool definition structs
├── builtin_tools.cr     # Built-in tools (ReadFile, ListDirectory)
├── tool_executor.cr     # Routes tool calls to handlers
├── tool_formatter.cr    # Converts tool calls to natural language
├── context_store.cr     # Short-term conversation context
├── context_manager.cr   # Combines context + memory
├── logger.cr            # Logging abstractions
└── memory_store.cr      # Long-term memory with consolidation

spec/
├── *_spec.cr            # One spec file per source file
└── spec_helper.cr       # Shared test helpers and dummy implementations
```

---

## Breaking Changes (v0.3.0)

**Client Interface**:
- `Client.execute()` now returns `Response` instead of `String`
- Access text via `response.content`
- `ChatFlow` handles this automatically
- Only affects code that calls `client.execute()` directly

**Migration**:
```crystal
# Before (v0.2.x)
response = client.execute(messages)
puts response  # String

# After (v0.3.0)
response = client.execute(messages)
puts response.content  # String? (from Response object)
```

---

## When Working on This Codebase

1. **Read Architecture First**: Check `ARCHITECTURE.md` for detailed component descriptions
2. **Follow TDD**: Write tests first, then implementation
3. **Test Everything**: All new code needs corresponding specs
4. **Use Dummy Implementations**: Isolate components in tests
5. **Keep It Simple**: Framework provides mechanisms, applications provide logic
6. **Natural Language**: Store tool interactions as readable text, not raw JSON
7. **Safety First**: Validate inputs, enforce limits, handle errors gracefully
8. **Document Interfaces**: Public methods and contracts should be clear
9. **Preserve Backward Compatibility**: Use optional parameters when adding features
10. **Run Full Test Suite**: `crystal spec` should always pass before committing
