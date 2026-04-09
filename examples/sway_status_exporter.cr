# examples/sway_status_exporter.cr
# Copyright (C) 2026 Cameron Carroll
# Licensed under the AGPL-3.0. See LICENSE for details.
#
# This example demonstrates how to consume Mantle's status events and export them
# to a file, which is perfect for desktop environments like Sway/i3 where tools
# like Waybar or i3blocks can display the current status.

require "../src/mantle"

# Path configuration - easily configurable by a consumer
STATUS_FILE_PATH = ENV["MANTLE_STATUS_FILE"]? || "/tmp/empaws_status.txt"

puts "Setting up Sway Status Exporter"
puts "Target file: #{STATUS_FILE_PATH}"
puts "Tip: View status using `tail -f #{STATUS_FILE_PATH}`"
puts ""

# Ensure we write a default empty state on startup
File.write(STATUS_FILE_PATH, "Idle")

# We use a Channel to avoid blocking the main thread when file IO happens.
# This prevents status tracking from slowing down the LLM integration!
status_channel = Channel(Symbol).new

# Set up the callback to receive updates from Mantle and forward them to the channel
Mantle.on_status_update = ->(flag : Symbol) do
  status_channel.send(flag)
end

# Spawn a dedicated background worker to write status changes to the file.
spawn do
  loop do
    # Block until a new status flag arrives
    flag = status_channel.receive

    # Map our internal symbols to pretty strings
    # We do not append a newline, as tools like Waybar often read raw files directly
    status_string = case flag
                    when :thinking
                      "Thinking"
                    when :tool_loop
                      "Tool_loop"
                    when :idle
                      "Idle"
                    when :memory_consolidation
                      "Consolidating"
                    else
                      # Generic capitalization fallback for any custom statuses
                      flag.to_s.capitalize
                    end

    begin
      File.write(STATUS_FILE_PATH, status_string)
      # Uncomment to see live updates in the console
      # puts "[Sway Exporter Worker] Wrote status: '#{status_string}' to #{STATUS_FILE_PATH}"
    rescue ex
      puts "Error writing status file: #{ex.message}"
    end
  end
end

puts "Simulating a workload to see the exporter in action..."

# Let's mock a sequence of events a standard Mantle process might undergo:
sleep 1.seconds

puts "1. Receiving user prompt, beginning to think..."
Mantle.emit_status(:thinking)
sleep 2.seconds

puts "2. Requesting a tool call..."
Mantle.emit_status(:tool_loop)
sleep 2.seconds

puts "3. Got tool response, thinking more..."
Mantle.emit_status(:thinking)
sleep 2.seconds

puts "4. Finished! Context got full, so consolidating memory..."
Mantle.emit_status(:memory_consolidation)
sleep 2.seconds

puts "5. Operation completely done, returning to idle..."
Mantle.emit_status(:idle)
sleep 1.seconds

puts "\nExample complete! You can see the last written state in #{STATUS_FILE_PATH}"
