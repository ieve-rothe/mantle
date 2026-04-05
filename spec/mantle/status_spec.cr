require "../spec_helper"
require "../../src/mantle/status"

describe Mantle::Status do
  before_each do
    Mantle::Status.clear
  end

  it "starts empty" do
    # Arrange & Act (none)

    # Assert
    Mantle::Status.all.should be_empty
  end

  it "can add a flag" do
    # Arrange
    flag = :test_flag

    # Act
    Mantle::Status.add(flag)

    # Assert
    Mantle::Status.has?(flag).should be_true
    Mantle::Status.all.should eq([flag])
  end

  it "ignores duplicate flags" do
    # Arrange
    flag = :test_flag

    # Act
    Mantle::Status.add(flag)
    Mantle::Status.add(flag)

    # Assert
    Mantle::Status.all.should eq([flag])
  end

  it "can remove a flag" do
    # Arrange
    flag = :test_flag
    Mantle::Status.add(flag)

    # Act
    Mantle::Status.remove(flag)

    # Assert
    Mantle::Status.has?(flag).should be_false
    Mantle::Status.all.should be_empty
  end

  it "can check if a flag exists" do
    # Arrange
    existing_flag = :existing_flag
    missing_flag = :missing_flag
    Mantle::Status.add(existing_flag)

    # Act
    has_existing = Mantle::Status.has?(existing_flag)
    has_missing = Mantle::Status.has?(missing_flag)

    # Assert
    has_existing.should be_true
    has_missing.should be_false
  end

  it "can clear all flags" do
    # Arrange
    Mantle::Status.add(:flag1)
    Mantle::Status.add(:flag2)

    # Act
    Mantle::Status.clear

    # Assert
    Mantle::Status.all.should be_empty
  end
end
