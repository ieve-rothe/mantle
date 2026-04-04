# Tool Calling Implementation - Simple Interface Guide

This guide explains the tool calling interfaces in plain terms. Think of it like a user manual for the new tool calling features.

## What Changed?

Your LLM can now call functions! Before, it could only return text. Now it can say "I need to call read_file()" and the framework will actually do it.

---

## The Big Picture (5 Steps)

1. **You define tools** - Tell the LLM what functions are available
2. **You call flow.run()** - Pass your message + tools
3. **LLM decides** - "Should I call a tool or just respond?"
4. **Framework executes** - If LLM wants a tool, framework runs it
5. **Loop continues** - Framework sends results back to LLM until it's done

---

## Key Interfaces You'll Use

### 1. Defining a Tool

**What it is**: A JSON schema that describes a function to the LLM

**How to create one**:
```crystal
my_tool = Mantle::Tool.new(
  function: Mantle::FunctionDefinition.new(
    name: "get_weather",                    # Function name
    description: "Get weather for a city",  # What it does
    parameters: Mantle::ParametersSchema.new(
      properties: {
        "city" => Mantle::PropertyDefinition.new(
          type: "string",                   # Parameter type
          description: "City name"          # What it's for
        )
      },
      required: ["city"]                    # Which params are mandatory
    )
  )
)
```

**The structs**:
- `Tool` - Top wrapper (you always create this)
- `FunctionDefinition` - Name + description + parameters
- `ParametersSchema` - Defines what params the function takes
- `PropertyDefinition` - Individual parameter (type + description)

---

### 2. Using Built-in Tools

**What they are**: Two tools the framework provides (read files, list directories)

**How to use them**:
```crystal
# Step 1: Pick which built-in tools you want
builtins = [
  Mantle::BuiltinTool::ReadFile,
  Mantle::BuiltinTool::ListDirectory
]

# Step 2: Configure safety (what paths are allowed)
builtin_config = Mantle::BuiltinToolConfig.new(
  working_directory: Dir.current,      # Base directory
  allowed_paths: [Dir.current, "/tmp"] # Optional: allow more paths
)

# Step 3: Pass them to flow.run()
flow.run(
  "List files in current directory",
  builtins: builtins,
  builtin_config: builtin_config,
  on_response: ->(response : String) { puts response }
)
```

**Safety rules**:
- By default: Can only access `working_directory`
- With `allowed_paths`: Can access those directories too
- Prevents sneaky paths like `../../etc/passwd`

---

### 3. Creating Custom Tools

**What they are**: Your own functions that the LLM can call

**How to make one** (2 steps):

**Step 1: Define the tool** (same as above):
```crystal
time_tool = Mantle::Tool.new(
  function: Mantle::FunctionDefinition.new(
    name: "get_current_time",
    description: "Get current time in UTC",
    parameters: Mantle::ParametersSchema.new(
      properties: {} of String => Mantle::PropertyDefinition
    )
  )
)
```

**Step 2: Implement the logic**:
```crystal
tool_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
  case name
  when "get_current_time"
    # Your logic here
    %({"time":"#{Time.utc.to_s}"})
  else
    %({"error":"Unknown tool: #{name}"})
  end
}
```

**Step 3: Use it**:
```crystal
flow.run(
  "What time is it?",
  custom_tools: [time_tool],
  tool_callback: tool_callback,
  on_response: ->(response : String) { puts response }
)
```

**Important**: Your callback must return a JSON string. That's what the LLM will see.

---

### 4. The ToolEnabledChatFlow Interface

**What it is**: The flow that handles tool calling automatically

**Full signature** (with all parameters):
```crystal
flow.run(
  msg : String,                         # User's message
  builtins: [...],                      # Built-in tools to enable
  custom_tools: [...],                  # Your custom tools
  tool_callback: ->(...),               # Your function to execute custom tools
  builtin_config: BuiltinToolConfig,    # Safety config for built-ins
  max_iterations: 10,                   # Safety limit (default: 10)
  on_response: ->(String) { ... }       # Called when LLM is done
)
```

**You only need what you're using**:
- Built-ins only? Just pass `builtins` and `builtin_config`
- Custom only? Just pass `custom_tools` and `tool_callback`
- Both? Pass all of them

---

## The Main Interfaces (What You'll Actually Touch)

### Creating a Flow

```crystal
flow = Mantle::ToolEnabledChatFlow.new(
  context_manager,  # Manages conversation
  client,          # Talks to LLM
  logger          # Logs everything
)
```

Same as regular `ChatFlow`, just use `ToolEnabledChatFlow` instead.

---

### Built-in Tool Config

```crystal
config = Mantle::BuiltinToolConfig.new(
  working_directory: String,    # Where relative paths start
  allowed_paths: Array(String)? # Optional: extra allowed directories
)
```

---

### Tool Callback Signature

```crystal
->(
  tool_name : String,                    # Which tool to run
  arguments : Hash(String, JSON::Any)   # What params were passed
) : String                               # Return JSON string
```

**Example**:
```crystal
tool_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
  city = args["city"].as_s
  %({"weather":"sunny","temp":72})
}
```

---

## What Happens Under the Hood (Simplified)

1. **You call flow.run()** with a message and tools
2. **Framework sends** message + tool definitions to LLM
3. **LLM responds** with either:
   - Text: "The weather is sunny" → Done!
   - Tool call: `{"name":"get_weather","args":{"city":"SF"}}` → Continue...
4. **Framework executes** the tool call
5. **Framework converts** result to natural language: "Called get_weather(city: SF). Result: sunny, 72°F"
6. **Framework sends** that back to LLM
7. **Loop repeats** until LLM responds with just text (no more tool calls)

---

## Common Patterns

### Pattern 1: Read a File

```crystal
flow.run(
  "Read README.md",
  builtins: [Mantle::BuiltinTool::ReadFile],
  builtin_config: Mantle::BuiltinToolConfig.new(Dir.current),
  on_response: ->(r : String) { puts r }
)
```

### Pattern 2: Custom Tool

```crystal
# Define
calculator = Mantle::Tool.new(...)

# Implement
calc_callback = ->(name : String, args : Hash(String, JSON::Any)) : String {
  a = args["a"].as_i
  b = args["b"].as_i
  %({"result":#{a + b}})
}

# Use
flow.run("What's 5 + 3?", custom_tools: [calculator], tool_callback: calc_callback, ...)
```

### Pattern 3: Mix Built-in + Custom

```crystal
flow.run(
  "Read config.json and calculate the sum",
  builtins: [Mantle::BuiltinTool::ReadFile],
  custom_tools: [calculator],
  builtin_config: config,
  tool_callback: calc_callback,
  on_response: ->(r : String) { puts r }
)
```

---

## Safety Features You Should Know

### Max Iterations
- Prevents infinite loops
- Default: 10 iterations
- LLM calls tool → framework executes → LLM calls another → ... (counts as iterations)
- If exceeded: Raises exception

### Path Validation
- Built-in tools check paths before accessing
- Blocks `../../../etc/passwd` type attacks
- Relative paths resolved against `working_directory`

### Error Handling
- If a tool fails, it returns JSON: `{"error":"reason"}`
- LLM sees the error and can try something else
- Other tools still run (one failure doesn't stop everything)

---

## The Breaking Change (If You Care)

**Before** (v0.2.x):
```crystal
response = client.execute(messages)  # Returns String
puts response
```

**After** (v0.3.0):
```crystal
response = client.execute(messages)  # Returns Response object
puts response.content      # The text (String?)
puts response.tool_calls  # Array of tool calls (if any)
```

**Good news**: If you're using `ChatFlow`, it still works the same. Only matters if you call `client.execute()` directly.

---

## Quick Reference

### What You Define

| Thing | What It Is |
|-------|-----------|
| `Tool` | A function the LLM can call |
| `BuiltinTool` | Enum: `ReadFile` or `ListDirectory` |
| `BuiltinToolConfig` | Safety settings for built-in tools |
| Tool callback | Your function that executes custom tools |

### What You Get Back

| Thing | What It Is |
|-------|-----------|
| `on_response` callback | Called when LLM gives final answer |
| Response string | The LLM's final text response |

### What Happens Automatically

- Tool execution (you just provide the callback)
- Converting results to natural language
- Adding tool interactions to conversation context
- Looping until LLM is satisfied
- Safety checks (path validation, iteration limits)

---

## That's It!

**TL;DR**:
1. Define tools (or use built-ins)
2. Pass them to `ToolEnabledChatFlow.run()`
3. LLM calls tools as needed
4. You get the final answer in `on_response`

The framework handles all the looping, formatting, and safety stuff for you.
