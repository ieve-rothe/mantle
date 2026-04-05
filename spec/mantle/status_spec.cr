require "../spec_helper"
require "../../src/mantle/status"

describe Mantle::Status do
  before_each do
    Mantle::Status.clear
  end

  it "starts empty" do
    Mantle::Status.all.should be_empty
  end

  it "can add a flag" do
    Mantle::Status.add(:test_flag)
    Mantle::Status.has?(:test_flag).should be_true
    Mantle::Status.all.should eq([:test_flag])
  end

  it "ignores duplicate flags" do
    Mantle::Status.add(:test_flag)
    Mantle::Status.add(:test_flag)
    Mantle::Status.all.should eq([:test_flag])
  end

  it "can remove a flag" do
    Mantle::Status.add(:test_flag)
    Mantle::Status.remove(:test_flag)
    Mantle::Status.has?(:test_flag).should be_false
    Mantle::Status.all.should be_empty
  end

  it "can check if a flag exists" do
    Mantle::Status.has?(:missing_flag).should be_false
    Mantle::Status.add(:existing_flag)
    Mantle::Status.has?(:existing_flag).should be_true
  end

  it "can clear all flags" do
    Mantle::Status.add(:flag1)
    Mantle::Status.add(:flag2)
    Mantle::Status.clear
    Mantle::Status.all.should be_empty
  end
end
