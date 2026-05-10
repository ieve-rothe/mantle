require "benchmark"
require "../src/mantle/memory_store"
require "file_utils"

# Mock squishifier that does minimal work
squishifier = ->(messages : Array(String)) : String {
  "Summary of #{messages.size} messages"
}

file_path = "benchmarks/test_memory.json"
FileUtils.rm_rf(file_path)

# Parameters to trigger many cascades and writes
# capacity=10, target=2 => ingest_step_size=8
store = Mantle::JSONLayeredMemoryStore.new(file_path, 10, 2, squishifier)

# We want to trigger the while loop in cascade multiple times.
# cascade(-1) is called by ingest.
# In cascade(-1), source is ingest_pending.
# chunk_size is source.size for layer -1.
# So if we ingest 100 messages at once, it processes them all in one go?
# Wait, let's re-read cascade:
# chunk_size = current_layer_index == -1 ? source.size : @ingest_step_size
# while source.size >= chunk_size && chunk_size > 0
#   ...
#   source.shift(chunk_size)
#   ...
#   chunk_size = current_layer_index == -1 ? source.size : @ingest_step_size

# If current_layer_index == -1, after shift(chunk_size), source.size becomes 0.
# So the while loop for layer -1 runs only ONCE.

# BUT, it calls cascade(target_layer_index) which is cascade(0).
# In cascade(0):
# chunk_size = @ingest_step_size (which is 8)
# If @layers[0] has say 40 messages, then the while loop will run 40/8 = 5 times.
# In each iteration of this while loop, save_memories_to_json is called.

# To trigger this, we need to fill layer 0.

# Fill layer 0 nearly to capacity (10)
9.times { store.ingest(["message"]) }
# Now @layers[0] has 9 summaries.

puts "Starting benchmark..."
Benchmark.bm do |x|
  x.report("ingest with cascade") do
    # This ingest will add 1 message to ingest_pending, then cascade(-1)
    # cascade(-1) will squish that 1 message and add it to @layers[0].
    # Now @layers[0] has 10 messages.
    # @layers[0].size >= @layer_capacity (10) is true.
    # It calls cascade(0).
    # In cascade(0), source is @layers[0], size 10.
    # chunk_size = @ingest_step_size = 8.
    # while 10 >= 8:
    #   squish 8 messages, @layers[0] size becomes 2.
    #   @layers[1] gets 1 summary.
    #   save_memories_to_json CALLED HERE.
    #   chunk_size = 8.
    #   2 >= 8 is false. loop ends.

    # To make it run more times, we need a larger @layers[0] before it triggers.
    # But cascade is called whenever we reach capacity.

    # Wait, if I manually push many items into @layers[0] and then call cascade...
    # JSONLayeredMemoryStore doesn't expose layers easily but it's a property.

    100.times do
      store.ingest(["message"])
    end
  end
end

FileUtils.rm_rf(file_path)
