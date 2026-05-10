# examples/01_basic_client.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# Level 1: Basic Client
#
# This example demonstrates the absolute minimum required to talk to an LLM
# using Mantle. We don't use any Flows, Context Managers, or Memory stores here,
# we just use the LlamaClient to send a prompt and get a response.

require "../src/mantle"

puts "--- Level 1: Basic Client ---"

# 1. Configure the model
# You need to define which model you want to talk to and what URL the API lives at.
# We are assuming you have Ollama running locally.
config = Mantle::ModelConfig.new(
  model_name: "gpt-oss:20b",
  stream: false,
  temperature: 0.7,
  top_p: 0.85,
  max_tokens: 1000,
  api_url: "http://localhost:11434/api/chat"
)

# 2. Initialize the Client
client = Mantle::LlamaClient.new(config)

# 3. Create a payload
# The client expects an array of messages representing the conversation history.
messages = [
  {"role" => "system", "content" => "You are a helpful assistant. Reply in exactly one sentence."},
  {"role" => "user", "content" => "Why is the sky blue?"},
]

puts "Sending request to the model..."

# 4. Send the request
# We pass the messages to the client's `execute` method and it returns a Response object.
response = client.execute(messages)

puts "\nModel Response:"
puts response.content

puts "\n--- Finished ---"
