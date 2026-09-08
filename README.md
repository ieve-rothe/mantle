# mantle
A Crystal Lang framework for abstracting LLM interactions into composable Step execution pipelines and strongly-typed outcomes.

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
       github: ieve-rothe/mantle
   ```

2. Run `shards install`

## Usage

Mantle is a framework to abstract details of communication to LLMs away, to help keep the application layer focused on... application stuff.

1. The Most Basic Client
> See [example: basic client](examples/01_basic_client.cr)
- **Client**: Handles sending message and getting a response from an LLM provider (currently supporting Ollama via `Mantle::Clients::OllamaClient`), with configuration set by a `Mantle::Clients::ModelConfig` object.

2. Context and Memory Management
> See [example: step and context](examples/02_chat_flow.cr)
- **Context Store**: Tracks the ongoing back and forth conversation between the user and the bot. Stored in JSON (`Mantle::JSONContextStore`), with optional ephemeral system prompt support.
- **Context Cascade and Memory Store**: To help avoid context dilution during long sessions or ongoing interactions, Mantle implements a summarization cascade with configurable thresholds based on a rough token counting heuristic. 
  - When context exceeds the `token_hardmax` target, we run summarization using `Mantle::Squishifiers`, asking the model to summarize messages to return to `token_target`. Those messages are moved to `Mantle::JSONLayeredMemoryStore`.
- **Context Manager**: Coordinates putting messages into context/memory, and getting current view of context by concatenating memory layers with context store view.

3. Step Execution Pipeline and Tool Calling
> See [example: tool calling](examples/03_tool_calling.cr)
- **Step**: `Mantle::Step` is a pure inference pipeline decoupled from storage persistence. It consumes messages and returns a strongly typed `Mantle::StepResult(String, Mantle::StepError)`.
- **StepResult**: Encapsulates outcome state: `.ok?`, `.err?`, `.unwrap`, `.thinking`, `.iterations`, and `.raw_response`.
- **Domain Errors**: Standardized in `Mantle::StepError` (`MalformedOutput`, `MaxIterationsReached`, `ClientFailure`, `ToolExecutionFailure`).
- **Tool Calling**: `Mantle::Tools::Tool` supports inline executable blocks or handlers. `Step` coordinates bounded tool loops up to `max_iterations`, safely handling tool outputs or returning typed errors without throwing unexpected exceptions.

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
