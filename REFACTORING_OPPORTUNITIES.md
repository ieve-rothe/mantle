# Mantle Refactoring Opportunities

This document outlines several opportunities for refactoring the Mantle framework. The primary goal is to improve maintainability and readability, with a secondary focus on testability, by reorganizing files, defining clearer namespaces, and decoupling dependencies.

## 1. Directory Reorganization & Namespacing

The framework is currently flat within `src/mantle/`. As the project grows, it would be beneficial to group related concepts into subdirectories to make the codebase easier to navigate.

**Proposed Structure:**

*   `src/mantle/core/`: Contains fundamental framework logic.
    *   `client.cr`
    *   `flow.cr`
    *   `status.cr`
*   `src/mantle/memory/`: Logic related to state and history.
    *   `context_manager.cr`
    *   `context_store.cr` (Split into interface/implementations)
    *   `memory_store.cr` (Split into interface/implementations)
    *   `squishifiers.cr`
*   `src/mantle/tools/`: All tool execution, definition, and formatting logic.
    *   `tools.cr` (Base interfaces)
    *   `tool_executor.cr`
    *   `tool_formatter.cr`
    *   `builtin_tools/` (Subdirectory for individual built-in tools)
*   `src/mantle/logging/`: Logging facilities.
    *   `logger.cr`
    *   `app_logger.cr`

## 2. Decoupling Dependencies and Interfaces

Currently, there are tight couplings between components that make testing harder and limit extensibility.

**Opportunities:**

*   **Abstract Memory Store:** `ContextManager` currently hardcodes a dependency on `JSONLayeredMemoryStore`.
    *   **Action:** Introduce a base `MemoryStore` abstract class or module. `ContextManager` should depend on the `MemoryStore` interface, not the concrete `JSON` implementation. This allows for in-memory or database-backed alternatives in the future and simplifies mocking during tests.
*   **Abstract I/O from State:** `JSONContextStore` and `JSONLayeredMemoryStore` directly perform file I/O operations (e.g., `File.write`, `File.read`).
    *   **Action:** Extract the persistence layer (e.g., a `StorageAdapter` interface with a `JSONStorageAdapter` implementation). This separation of concerns allows the in-memory state manipulation to be tested completely independent of the file system.
*   **ContextStore interface definition:** `ContextStore` provides some stubbed methods for the base class instead of enforcing an abstract implementation. Consider marking these abstract.

## 3. Splitting Large Files

Some files contain multiple responsibilities and implementations that should be split into smaller, more focused files.

**Opportunities:**

*   **`builtin_tools.cr`:** This file is very long (11k bytes) and contains the `BuiltinTool` enum, `BuiltinToolRegistry`, `BuiltinToolConfig`, `BuiltinToolExecutor`, and the specific implementations for every built-in tool (e.g., `read_file`, `write_file`).
    *   **Action:** Move each built-in tool's logic into its own file (e.g., `src/mantle/tools/builtin/read_file.cr`) and keep only the registry/executor logic in a core tools file.
*   **`context_store.cr`:** Contains the base `ContextStore` class, `EphemeralSlidingContextStore`, and `JSONContextStore`.
    *   **Action:** Split these into three separate files: `context_store.cr` (base interface), `ephemeral_sliding_context_store.cr`, and `json_context_store.cr`.
*   **`flow.cr`:** Contains the base `Flow`, `ChatFlow`, and `ToolEnabledChatFlow`.
    *   **Action:** Extract these into separate files within a `src/mantle/flow/` directory.

## 4. Simplifying Complex Logic

*   **`ContextManager#consolidate_memory` / `JSONLayeredMemoryStore#cascade`:** The memory consolidation and cascade logic is complex and relies heavily on recursion and multiple states.
    *   **Action:** Review the cascade logic in `JSONLayeredMemoryStore` to see if the recursion can be simplified or replaced with an iterative approach that is easier to trace and test. The chunking and batching logic could potentially be extracted into a separate pure-function helper to make it more testable.
