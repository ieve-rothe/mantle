---
ID: TKT-009
Title: Decompose Builtin Tools into Modular Handlers, Extract FileSystemSandbox, and Unify ToolExecutor
Status: Closed
Priority: High
---

## 1. User Need
As an agent framework developer and consumer application developer, I need built-in tools to be modular, cohesive, and easily extensible, rather than bundled into a 630-line monolithic file with a closed enum and hardcoded routing in `ToolExecutor`. I need file security / sandboxing to be an independent, testable module, and tools to be first-class citizens that carry their own execution handlers.

## 2. Specification
1. **Extract `FileSystemSandbox`**:
   - Move path sanitization, symlink traversal checking (`safe_realpath`, `is_subpath?`), allowed path validation, autonomous zone enforcement, and timestamped backup file creation/rotation from `BuiltinToolExecutor` into `Mantle::Tools::FileSystemSandbox`.
2. **Decompose `builtin_tools.cr` into Modular Handlers**:
   - Create `src/mantle/tools/builtin/` directory with dedicated modules:
     - `read_file.cr` (`Mantle::Tools::Builtin::ReadFile`)
     - `write_file.cr` (`Mantle::Tools::Builtin::WriteFile`)
     - `list_directory.cr` (`Mantle::Tools::Builtin::ListDirectory`)
     - `search_files.cr` (`Mantle::Tools::Builtin::SearchFiles`)
     - `notify_send.cr` (`Mantle::Tools::Builtin::NotifySend`)
   - Each module provides its schema (`definition : FunctionDefinition`) and a factory method (`create(...) : Tool`) that returns a standard `Tool` with its execution `handler` attached.
   - Provide an aggregator helper `Mantle::Tools::Builtin.all(sandbox, ...)` in `src/mantle/tools/builtin.cr`.
   - Delete `src/mantle/tools/builtin_tools.cr`.
3. **Unify `ToolExecutor`**:
   - Remove `BUILTIN_TOOL_NAMES` array, `is_builtin_tool?`, and `builtin_config`.
   - Update `ToolExecutor` to accept `tools : Array(Mantle::Tools::Tool)`.
   - Route execution dynamically to matching `Tool` instances via `tool.execute(arguments)` before falling back to `custom_callback`.
   - Expose `execute(name : String, arguments : Hash(String, JSON::Any)) : String` for single-tool execution.
4. **SemVer Major Bump**:
   - Bump version from `1.2.0` to `2.0.0` in `shard.yml`.

## 3. Migration Guide for Codebots & Upgrading Applications

> [!IMPORTANT]
> **Breaking Changes in Mantle 2.0.0:**
> - `Mantle::Tools::BuiltinTool` (enum) is removed.
> - `Mantle::Tools::BuiltinToolRegistry` is removed.
> - `Mantle::Tools::BuiltinToolConfig` and `Mantle::Tools::BuiltinToolExecutor` are removed.
> - `Mantle::Tools::ToolExecutor::BUILTIN_TOOL_NAMES` is removed.
> - `Mantle::Tools::ToolExecutor` takes `tools : Array(Tool)` instead of `builtin_config`.

### Pattern Migration for Host Applications (e.g. `empaws`)

#### Before (Mantle 1.x):
```crystal
# 1. Configured via BuiltinToolConfig
builtin_config = Mantle::Tools::BuiltinToolConfig.new(
  working_directory: sandbox_path,
  allowed_paths: [allowed_dir],
  notify_icon: icon_path,
  autonomous_zone_paths: [auto_zone],
  file_backup_count: 3
)

# 2. Hardcoded enum array & separate registry lookup
builtins = [
  Mantle::Tools::BuiltinTool::ReadFile,
  Mantle::Tools::BuiltinTool::ListDirectory,
  Mantle::Tools::BuiltinTool::NotifySend,
  Mantle::Tools::BuiltinTool::WriteFile,
]
builtin_executor = Mantle::Tools::BuiltinToolExecutor.new(builtin_config, bot_name: "Assistant")
all_tools = Mantle::Tools::BuiltinToolRegistry.definitions_for(builtins) + custom_tools

# 3. Routing required checking BUILTIN_TOOL_NAMES
tool_callback = ->(name : String, args : Hash(String, JSON::Any)) {
  if Mantle::Tools::ToolExecutor::BUILTIN_TOOL_NAMES.includes?(name)
    builtin_executor.execute(name, args)
  else
    custom_handler(name, args)
  end
}
```

#### After (Mantle 2.0.0):
```crystal
# 1. Configured via FileSystemSandbox
sandbox = Mantle::Tools::FileSystemSandbox.new(
  working_directory: sandbox_path,
  allowed_paths: [allowed_dir],
  autonomous_zone_paths: [auto_zone],
  file_backup_count: 3
)

# 2. Instantiate tools directly or via Builtin.all
builtin_tools = [
  Mantle::Tools::Builtin::ReadFile.create(sandbox),
  Mantle::Tools::Builtin::ListDirectory.create(sandbox),
  Mantle::Tools::Builtin::NotifySend.create(bot_name: "Assistant", icon: icon_path),
  Mantle::Tools::Builtin::WriteFile.create(sandbox),
]
# Or all at once:
# builtin_tools = Mantle::Tools::Builtin.all(sandbox, bot_name: "Assistant", notify_icon: icon_path)

# 3. If using Mantle::Step with tool_callback logging wrapper:
# Pass definitions without handler so Step routes to tool_callback, where logging hooks intercept:
all_tools = builtin_tools.map { |t| Mantle::Tools::Tool.new(t.function) } + custom_tools

tool_callback = ->(name : String, args : Hash(String, JSON::Any)) {
  logger.log_call(name, args)
  result = if matched_tool = builtin_tools.find { |t| t.function.name == name }
             matched_tool.execute(args)
           else
             custom_handler(name, args)
           end
  logger.log_result(name, args, result)
  result
}

# 4. If using Mantle::Tools::ToolExecutor directly:
executor = Mantle::Tools::ToolExecutor.new(
  tools: builtin_tools + custom_tools_with_handlers,
  custom_callback: fallback_proc
)
executor.execute(tool_name, tool_args)
```

## 4. Verification & Validation (V&V)
* **Verification Plan:**
  - Update `spec/builtin_tools_spec.cr` to verify `FileSystemSandbox` and each `Builtin::*` tool.
  - Update `spec/tool_executor_spec.cr` to verify generic `ToolExecutor` tool registration and dispatch.
  - Run `crystal spec` in `mantle`.
* **Verification Evidence:**
  - `mantle`: `crystal spec` passed with 296 examples, 0 failures, 0 errors.
* **Validation Plan:**
  - Propagate changes to `empaws` (`empaws_app.cr`, `kernel.cr`, `hypervisor_spec.cr`).
  - Run `crystal spec` in `empaws`.
* **Validation Evidence:**
  - `empaws`: `crystal spec` passed with 233 examples, 0 failures, 0 errors.

## 5. Revision History
* 2026-09-25: Ticket created, implemented, verified, and closed alongside Mantle 2.0.0 release.
---
