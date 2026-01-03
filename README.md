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

```crystal
require "mantle"
```

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

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
