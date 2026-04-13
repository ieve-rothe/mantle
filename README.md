# mantle
A framework for abstracting LLM interactions into composable Flow objects, where a Flow is a self-contained block of work (eg planning, reflecting, or running tool call commands).

Intended to be a base layer for building LLM applications.

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

Mantle provides building blocks to construct robust applications using Large Language Models.

The primary concepts in Mantle are:
- **Clients**: Connect to an LLM provider (e.g. `Mantle::LlamaClient`).
- **Context Stores**: Track immediate, short-term conversational context (e.g. `Mantle::JSONContextStore`).
- **Memory Stores**: Handle long-term memory, summarization, and retention of historical conversation data (e.g. `Mantle::JSONLayeredMemoryStore`).
- **Context Managers**: Coordinate message flow between Context and Memory stores to keep LLM context windows manageable.
- **Flows**: The execution loops where work happens. A flow takes user input, passes it to a ContextManager and Client, and handles the response. (e.g. `Mantle::ChatFlow` or `Mantle::ToolEnabledChatFlow`).

### Basic Setup Example

Here is a simple example to set up a basic ChatFlow with Mantle:

```crystal
require "mantle"

# 1. Setup Client
client = Mantle::LlamaClient.new(
  Mantle::ModelConfig.new(
    model_name: "gpt-oss:20b",
    stream: false,
    temperature: 0.7,
    top_p: 0.85,
    max_tokens: 1000,
    api_url: "http://localhost:11434/api/chat"
  )
)

# 2. Setup Context Management
context_store = Mantle::JSONContextStore.new(
  system_prompt: "You are a helpful assistant.",
  context_file: "my_context.json"
)

memory_store = Mantle::JSONLayeredMemoryStore.new(
  memory_file: "my_memory.json",
  layer_capacity: 10,
  layer_target: 5,
  squishifier: Mantle::Squishifiers.build_basic_summarizer(client)
)

context_manager = Mantle::ContextManager.new(
  context_store: context_store,
  memory_store: memory_store,
  user_name: "User",
  bot_name: "Assistant",
  msg_target: 6,
  msg_hardmax: 12
)

# 3. Setup Flow
logger = Mantle::FileLogger.new("chat.log", "User", "Assistant")
flow = Mantle::ChatFlow.new(
  context_manager: context_manager,
  client: client,
  logger: logger
)

# 4. Run!
flow.run(
  msg: "Hello Mantle!",
  on_response: ->(resp : Mantle::Response) {
    puts "Assistant: #{resp.content}"
  }
)
```

Check out the `examples/` directory for progressive, heavily commented examples on how to build up to more complex setups like `ToolEnabledChatFlow`.

## Development

1. Run tests with `crystal spec`.
2. See `AGENTS.md` and `CLAUDE.md` for architectural guidelines.

## Contributing

1. Fork it (<https://github.com/your-github-user/mantle/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [ieve (Cameron Carroll)](https://github.com/CameronCarroll) - creator and maintainer

## License
Mantle is licensed under the GNU AGPL-3.0 license.
See the LICENSE file for details.
