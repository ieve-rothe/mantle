# Mantle Architecture

This document describes the internal architecture of the Mantle framework.

## Overview

Mantle is a Crystal framework for abstracting LLM interactions into composable Flow objects. It provides a low-level base layer for building LLM applications with a focus on separation of concerns: implementation details about _how_ to talk to models and structure loops belong in Mantle, while application-specific logic about _what_ an agent should achieve lives in the application layer.

## Core Components

### Flow (`src/mantle/flow.cr`)

**Purpose**: Base abstraction for LLM inference operations

**Key Classes**:
- `Flow`: Abstract base class for all flow types
- `ChatFlow`: Concrete implementation for basic chat interactions
- `ToolEnabledChatFlow`: Extends ChatFlow with tool calling loop functionality

**Responsibilities**:
- Represents self-contained blocks of work (planning, reflection, tool execution, etc.)
- Each flow has a `run(input, on_response)` method that assembles context, sends to client, and handles response
- Coordinates between: context store (manages conversation), client (API communication), and logger (output tracking)

**Design**: Uses composition over inheritance - Flow composes context_manager, client, and logger rather than inheriting functionality

---

### Client (`src/mantle/client.cr`)

**Purpose**: Abstraction for LLM API communication

**Key Classes**:
- `Client`: Abstract base class defining the contract for LLM API interactions
- `LlamaClient`: Concrete implementation for Ollama-compatible APIs
- `ModelConfig`: Record type for configuration (model name, streaming, temperature, top_p, max_tokens, api_url)
- `Response`: Return type containing optional `content` (text) and `tool_calls` (array)
- `ToolCall`: Represents a tool invocation from the LLM
- `ToolCallFunction`: Contains function name and arguments

**API**:
```crystal
abstract def execute(messages : Array(Hash(String, String)), tools : Array(Tool)? = nil) : Response
```

**Design Notes**:
- Abstract class enables testing with dummy implementations
- Returns `Response` instead of `String` to support tool calling
- Tool parameter is optional for backward compatibility
- Record type `ModelConfig` provides immutable configuration

---

### ContextStore (`src/mantle/context_store.cr`)

**Purpose**: Manages ongoing conversation context (short-term memory only, not identity or long-term memory)

**Implementations**:
- `EphemeralSlidingContextStore`: Maintains fixed number of recent messages in memory
- `JSONContextStore`: Persists sliding window to JSON file for cross-session continuity

**API**:
- `add_message(label : String, message : String)`: Add message to context
- `current_view : Array(Hash(String, String))`: Get current context as message array
- `prune(num : Int32)`: Manually remove oldest messages (JSONContextStore only)

**Message Format**: `{"role" => "user|assistant|system", "content" => "..."}`

**Design**: Multiple implementations with different retention strategies allow applications to choose appropriate context management

---

### ContextManager (`src/mantle/context_manager.cr`)

**Purpose**: Higher-level interface combining context and memory

**Responsibilities**:
- Bridges ContextStore (short-term) and MemoryStore (long-term)
- Provides `handle_user_message()` and `handle_bot_message()` convenience methods
- Assembles complete context view (system prompt + memory + conversation)

---

### Logger (`src/mantle/logger.cr`)

**Purpose**: Pluggable logging for tracking conversations

**Key Classes**:
- `Logger`: Abstract base class
- `FileLogger`: Writes formatted timestamped entries to file with ASCII dividers
- `DetailedLogger`: Extends FileLogger to write context, user messages, and bot messages to separate files

**Design**: Abstract class pattern enables testing with DummyLogger (no-op implementation)

---

### MemoryStore (`src/mantle/memory_store.cr`)

**Purpose**: Hierarchical long-term memory with automatic consolidation

**Implementation**: `JSONLayeredMemoryStore`

**Architecture**:
- Manages memory in layers: Layer 0 (recent summaries) → Layer 1 (older summaries) → Layer 2, etc.
- Messages from context are squishified (summarized) and added to Layer 0
- When a layer reaches capacity, oldest messages consolidate to the next layer

**Configuration**:
- `layer_capacity`: Maximum items per layer
- `layer_target`: Items remaining after consolidation
- `ingest_step_size = layer_capacity - layer_target`: Batch size for consolidation

**Persistence**: JSON file with `ingest_pending` (messages awaiting squishification) and `layers` arrays

**Fault Tolerance**: If squishifier fails, messages remain in `ingest_pending` for retry

---

## Tool Calling System

### Tool Definitions (`src/mantle/tools.cr`)

**Purpose**: Type-safe schema for defining tools that LLMs can invoke

**Structs** (all include `JSON::Serializable`):
- `Tool`: Top-level wrapper (type: "function")
- `FunctionDefinition`: Describes function with name, description, and parameters
- `ParametersSchema`: JSON schema for parameters (type: "object" with properties)
- `PropertyDefinition`: Individual parameter definition (type, description)

**Design**: Matches OpenAI/Ollama tool calling API format

---

### Built-in Tools (`src/mantle/builtin_tools.cr`)

**Purpose**: Framework-provided tools with safety controls

**Components**:
- `BuiltinTool`: Enum with values `ReadFile` and `ListDirectory`
- `BuiltinToolRegistry`: Maps enum values to Tool definitions
- `BuiltinToolExecutor`: Executes built-in tools with path validation
- `BuiltinToolConfig`: Controls filesystem access (working_directory, allowed_paths)

**Safety Model**:
- Default: Only allow access to `working_directory`
- Optional: Explicitly grant access via `allowed_paths` array
- Path validation prevents directory traversal attacks (e.g., `../../etc/passwd`)
- Relative paths are resolved against `working_directory`

**Return Format**: JSON with `{"success": true, "content": "..."}` or `{"error": "..."}`

---

### Tool Executor (`src/mantle/tool_executor.cr`)

**Purpose**: Coordinates execution of both built-in and custom tools

**Key Classes**:
- `ToolExecutor`: Routes tool calls to appropriate handlers
- `ToolResult`: Links tool call ID to execution result

**Routing Logic**:
- Checks function name against built-in tools list (`["read_file", "list_directory"]`)
- Routes to `BuiltinToolExecutor` for built-in tools
- Routes to application-provided callback for custom tools

**Error Handling**:
- Individual tool failures return error JSON
- Execution continues for remaining tools
- Errors don't stop the entire flow

---

### Tool Formatter (`src/mantle/tool_formatter.cr`)

**Purpose**: Converts structured tool interactions to natural language for context storage

**Functions**:
- `format_tool_call(tool_call)`: "Called read_file(file_path: 'test.txt')"
- `format_tool_result(id, result)`: "Result from call_123: Hello, World!"
- `format_assistant_message_with_tool_calls(content, calls)`: Combines content and calls

**Design Rationale**:
- Natural language in context improves LLM understanding
- Human-readable conversation history
- Works better with memory consolidation (squishification)
- Automatically truncates long results (max 500 chars)

---

### ToolEnabledChatFlow (`src/mantle/flow.cr`)

**Purpose**: Extends ChatFlow with automatic tool calling loop

**Tool Call Loop**:
1. Sends user message with merged tool definitions to LLM
2. If response contains tool calls: execute tools, add natural language results to context, continue
3. If response contains only text: complete and return to application
4. Enforces `max_iterations` limit (default: 10) to prevent infinite loops

**Parameters**:
- `builtins`: Array of `BuiltinTool` enum values to enable
- `custom_tools`: Array of `Tool` definitions
- `tool_callback`: Proc for executing custom tools
- `builtin_config`: Filesystem safety configuration
- `max_iterations`: Safety limit

**Context Integration**: All tool interactions stored as natural language in conversation history

---

## Design Patterns

### Abstract Classes for Contracts
- `Client` and `Logger` use abstract base classes
- Enables testing with dummy implementations
- Supports alternative implementations (e.g., different LLM providers)

### Record Types for Configuration
- `ModelConfig` uses Crystal's `record` macro
- Immutable configuration objects
- Positional arguments (not named)

### Composition Over Inheritance
- Flow composes context_manager, client, and logger
- Components can be swapped independently
- Easier to test in isolation

### Separation of Concerns
- **Context**: Short-term conversation memory (ContextStore)
- **Memory**: Long-term summarized memory (MemoryStore)
- **Identity**: Not yet implemented (future: system prompts, personality)

---

## File Organization

```
src/mantle/
├── flow.cr              # Flow abstractions, ChatFlow, and ToolEnabledChatFlow
├── client.cr            # LLM client abstractions, Response types, and Ollama implementation
├── tools.cr             # Tool definition structs (Tool, FunctionDefinition, etc.)
├── builtin_tools.cr     # Built-in tool enum, registry, executor, and safety config
├── tool_executor.cr     # Coordinates built-in and custom tool execution
├── tool_formatter.cr    # Converts tool interactions to natural language
├── context_store.cr     # Context management with multiple strategies
├── context_manager.cr   # High-level interface combining context and memory
├── logger.cr            # Logging abstractions and file-based implementations
├── memory_store.cr      # Hierarchical long-term memory with consolidation
└── squishifiers.cr      # Helper functions for building summarization procs

spec/
├── context_store_spec.cr    # Comprehensive context store tests
├── client_spec.cr           # Client and Response type tests
├── tools_spec.cr            # Tool definition struct tests
├── builtin_tools_spec.cr    # Built-in tool registry and executor tests
├── tool_formatter_spec.cr   # Tool formatting tests
├── tool_executor_spec.cr    # Tool execution coordinator tests
├── tool_flow_spec.cr        # ToolEnabledChatFlow tests
└── mantle_spec.cr          # Main library tests

examples/
├── basic_app.cr         # Basic usage example
├── logger_test.cr       # Logger demonstration
└── tool_calling_app.cr  # Tool calling demonstration with built-in and custom tools
```

---

## Implementation Details

### JSONLayeredMemoryStore Recursive Consolidation

The layered memory consolidation uses recursive `cascade()` calls to move summaries between layers. This is a complex implementation worth understanding:

**Capacity Check Timing**:
- Check capacity BEFORE adding to prevent filling beyond capacity
- Additional check AFTER processing ingest_pending ensures Layer 0 consolidates when full
- Do NOT add post-processing checks to recursive calls (prevents infinite cascade chains)

**Consolidation Flow**:
1. `ingest()` adds messages to `@ingest_pending`, then calls `cascade(-1)`
2. `cascade(-1)` squishifies all pending messages and adds each to Layer 0
3. When Layer 0 reaches capacity during cascade, recursively calls `cascade(0)`
4. `cascade(0)` batches `ingest_step_size` items from Layer 0, squishifies, adds to Layer 1
5. This continues recursively up the layer hierarchy as needed

**Preventing Infinite Recursion**:
- Safety limit: max layer index of 50 (reasonable for any realistic usage)
- The layer index itself serves as recursion depth
- Final consolidation check only for layer -1 (entry point), not for recursive calls

**Recommended Parameters**:
- `layer_capacity: 7-10`, `layer_target: 5`
- Avoid very small values like `capacity: 2, target: 1` (creates excessive layers)
- With realistic parameters, deep cascading requires significant message volume

**Test Design Insights**:
- Tests with unrealistic parameters revealed edge cases but were harder to reason about
- Deterministic squishifier in tests preserves message content in summaries
- When testing consolidation, check specific layer sections, not entire view

---

## Breaking Changes

### v0.2.x → v0.3.0: Tool Calling Support

**Client Interface Change**:
- `Client.execute()` now returns `Response` instead of `String`
- `Response` contains optional `content : String?` and `tool_calls : Array(ToolCall)?`
- Tool parameter added: `execute(messages, tools : Array(Tool)? = nil)`

**Migration**:
```crystal
# Before (v0.2.x)
response = client.execute(messages)
puts response  # String

# After (v0.3.0)
response = client.execute(messages)
puts response.content  # String?
puts response.tool_calls  # Array(ToolCall)?
```

**Impact**:
- `ChatFlow` automatically handles this (extracts `content` from Response)
- Custom Client implementations must update their return type
- Applications directly using Client need to update response handling
