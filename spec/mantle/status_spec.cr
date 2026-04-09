require "../spec_helper"
require "../../src/mantle/status"

describe Mantle do
  before_each do
    Mantle.on_status_update = nil
  end

  describe ".emit_status" do
    it "triggers the callback when a status is emitted" do
      received_flags = [] of Symbol

      Mantle.on_status_update = ->(flag : Symbol) do
        received_flags << flag
      end

      Mantle.emit_status(:test_flag)
      Mantle.emit_status(:another_flag)

      received_flags.should eq([:test_flag, :another_flag])
    end

    it "does nothing if no callback is registered" do
      # Should not raise any errors
      Mantle.emit_status(:orphaned_flag)
    end
  end
end
