# mantle
A Crystal Lang framework for abstracting LLM interactions into composable Flow objects, where a Flow is a self-contained block of work (eg planning, reflecting, or running tool call commands).

Intended to be a base layer for building LLM applications.

## Developed with AI Notice
ieve is not a software engineer, just a hobbyist. So I use heavy use of LLM tools to help me in a few ways:
1. Talking through architecture approaches or language features/patterns to accomplish what I want.
2. Use of Claude Code or Google Jules to implement features or do refactoring. It's probably about 50/50 hand coded and machine coded. The tests are mostly machine generated. Things that are boring are machine generated. I, just personally, would never get anywhere if I couldn't hand off big chunks to the machine.

However, my limit of use of AI is that I don't want to let the codebase get beyond my understanding. All architectural and design decisions are curated and reviewed by the human, at minimum.

## Separation of concerns
Mantle is intended to be pretty low level - if code is related to _how_ to talk to the model or _how_ to structure a loop, it should live here in Mantle.
If the code is related to _what_ an agent is trying to achieve, it should live at the application layer.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     mantle:
       github: CameronCarroll/mantle
   ```

2. Run `shards install`

## Usage

Mantle is a framework to abstract details of communication to LLMs away, to help keep the application layer focused on... application stuff.

1. The Most Basic Client
> See [example: basic client](examples/01_basic_client.cr)
- **Client**: Handles sending message and getting a response from an LLM provider (currently only supporting Ollama via `Mantle::LlamaClient`), with configuration set by a `Mantle::ModelConfig` object.

2. Chat Flow with Context and Memory Management
> See [example: chat flow](examples/02_chat_flow.cr)
- **Context Store**: Tracks the ongoing back and forth conversation between the user and the bot. (Also the system prompt is at the very top of context memory). New messages are appended to the bottom. Stored in JSON (`Mantle::JSONContextStore`), with optional ephemeral system prompt support.
- **Context Cascade and Memory Store**: To help avoid context dilution during long sessions or ongoing interactions, Mantle implements a summarization cascade with configurable thresholds based on a rough token counting heuristic. 
  - When context exceeds the `token_hardmax` target, we run an LLM flow using a `Mantle::Squishifiers` class method, asking the model to summarize enough messages to return us to `token_target`. Those messages are removed from context and moved to `Mantle::JSONLayeredMemoryStore`.
  - Memory stores themselves have a `layer_token_target` and `layer_token_hardmax`, so that when each memory layer reaches its threshold, those memory entries are sent through the Squishifier and cascade to the next layer of memory. (Currently internally hardcoded to a maximum of 50 layers. Surely 50 ought to be enough for anyone.)
- **Context Manager**: Coordinates putting messages into context/memory, and getting current view of context by concatenating memory layers with context store view.
- **Application Logger**: `Mantle::FileLogger` provides a bunch of individual log files to provide different views into the language model flow:
  - Application log - System messages
  - Last User Message (human readable)
  - Last Request File (JSON format request from last user message)
  - Last Bot Message (human readable)
  - Last Response File (JSON format response from last bot message)
  - Last Context Sent to Model (human readable, showing system prompt + memory layers + context window)
  - Ongoing Log (human readable running log of user messages and bot responses)
- **Chat Flow**: `Mantle::ChatFlow`: Finally, after all of this setup, we're ready to execute an interaction with the model. Mantle accepts a callback function from the application so that the application can handle the response however you like. You bring the message, you handle the response, and Mantle handles the client interaction, context and memory management and logging.

3. Tool Calling
> See [example: tool calling](examples/03_tool_calling.cr)
- **Tool Enabled Chat Flow**: Mantle provides a `Mantle::ToolEnabledChatFlow`, which initializes the same way as a normal ChatFlow, but accepts additional options at the time of calling flow.run...
  - Builtins array - Consists of a number of `Mantle::BuiltinTool` objects. (These are tools already included as part of the Mantle framework).
  - Custom tools array - Consists of a number of `Mantle::Tool` objects created at the application layer. Custom tools consists of a `Mantle::FunctionDefinition`, which contains a name, description, a `Mantle::ParametersSchema`, which in turn consists of `Mantle::PropertyDefinition`, and an array defining which of the parameters are required. Supposedly there was some design intent behind making things this convoluted but I don't remember what it is. Something about the OpenAI JSON Schema specification.
  - Custom tool handler - While the `Mantle::Tool` defines the tool at an interface level, the custom tool handler is used to route to and implement the business logic for the tool as a callback passed into the flow method.
- **Tool Security Boundaries**: Mantle uses a `Mantle::BuiltinToolConfig` to define the read and write boundaries and file backup option for agentic operation...
  - `allowed_paths`: Bot can read any files within allowed_paths.
  - `autonomous_zone_paths`: Defines sandbox folders where the agent is allowed to read or write.
  - `file_backup_count`: Mantle automatically creates a backup of any file the bot writes to in the background, and will automatically maintain N files up to this integer param, deleting N+1 on next write.
- **Tool iteration**: ``Mantle::ToolEnabledChatFlow` accepts a `max_iterations` parameter. When the model initiates a tool call, we will enter a loop up to this maximum number. If we get a text response back from the model, we end the loop and return the response. If the model initiates another tool call, we'll keep running tool calls up to the maximum. If we keep running tool calls up to the maximum, we provide a final prompt to the model without tools available asking it to provide a text response.

4. Advanced Features for Cognitive Architectures
> See `ARCHITECTURE.md` for detailed documentation

Mantle provides several advanced primitives designed for cognitive operating systems and multi-agent architectures:

- **Ephemeral System Blocks**: Dynamically inject temporary system messages (K-Lines, "Demon" instructions) into a single LLM call without persisting to storage. Useful for frame switching and context manipulation.

- **Invisible Appends**: Append backend routing instructions to user messages that appear in the LLM context but not in long-term memory. Prevents metadata from cluttering conversation history.

- **Dynamic System Prompt Updates**: Update the system prompt on any `ContextStore` or through the `ContextManager` mid-session (e.g. `@context_manager.update_system_prompt(new_prompt)`) to adapt context to changing cognitive tasks.

- **System Prompt Ephemeral Mode**: Configure `JSONContextStore` with `persist_system_prompt: false` to allow the application layer or Hypervisor to manage system prompts dynamically in memory without saving them to the JSON context files, preventing old system prompts from being restored on reload.

- **Hot-Swapping State Stores**: Safely replace ContextStore and MemoryStore mid-session for "hard shifts" between personas or conversation frames. Ensures data integrity through proper flushing.

- **Custom Tool Formatting**: Tool callbacks can return `formatted_override` to control how results appear in context, maintaining persona continuity when subagents need custom formatting.

- **Subagent Recursion Kill-Switch**: Framework-level depth tracking (`MAX_SUBAGENT_DEPTH = 1`) automatically strips tools at depth boundaries to prevent infinite recursion, runaway costs, and context collapse.

These features maintain Mantle's core principle: the framework provides agnostic *pipes*, while applications control the *content* and *timing*.

## Development

1. Run tests with `crystal spec`.
2. Bots: See `AGENTS.md` and `CLAUDE.md` for architectural guidelines.

## Contributing

1. Fork it (<https://github.com/ieve-rothe/mantle/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [ieve (Cam Carroll)](https://github.com/ieve-rothe) - creator and maintainer

## License
Mantle is licensed under the GNU AGPL-3.0 license.
See the LICENSE file for details.
