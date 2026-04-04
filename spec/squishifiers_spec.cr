# spec/squishifiers_spec.cr
require "./spec_helper"

# Mock client that captures the messages it receives
class CapturingClient < Mantle::Client
  property captured_messages : Array(Hash(String, String))? = nil
  property response_to_return : String

  def initialize(@response_to_return : String = "Mocked summary response")
  end

  def execute(messages : Array(Hash(String, String))) : String
    @captured_messages = messages
    @response_to_return
  end
end

# Mock client that always fails
class FailingClient < Mantle::Client
  def execute(messages : Array(Hash(String, String))) : String
    raise Exception.new("LLM service unavailable")
  end
end

describe Mantle::Squishifiers do
  describe ".build_basic_summarizer" do
    it "creates a proc that accepts an array of strings" do
      # Arrange
      client = CapturingClient.new
      squishifier = Mantle::Squishifiers.build_basic_summarizer(client)

      # Assert
      squishifier.should be_a(Proc(Array(String), String))
    end

    it "formats messages into proper chat format with system and user roles" do
      # Arrange
      client = CapturingClient.new("Summary result")
      squishifier = Mantle::Squishifiers.build_basic_summarizer(client)

      test_messages = [
        "[User] Hello there",
        "[Assistant] Hi back",
        "[User] How are you?"
      ]

      # Act
      result = squishifier.call(test_messages)

      # Assert - Check that client received properly formatted messages
      client.captured_messages.should_not be_nil
      messages = client.captured_messages.not_nil!

      messages.size.should eq(2)  # system + user message

      # First message should be system prompt
      messages[0]["role"].should eq("system")
      messages[0]["content"].should contain("Extract factual data")
      messages[0]["content"].should contain("bulleted list")

      # Second message should be user content with joined messages
      messages[1]["role"].should eq("user")
      messages[1]["content"].should contain("[User] Hello there")
      messages[1]["content"].should contain("[Assistant] Hi back")
      messages[1]["content"].should contain("[User] How are you?")
    end

    it "returns the stripped response from the client" do
      # Arrange
      client = CapturingClient.new("  Response with whitespace  \n")
      squishifier = Mantle::Squishifiers.build_basic_summarizer(client)

      test_messages = ["[User] Test message"]

      # Act
      result = squishifier.call(test_messages)

      # Assert
      result.should eq("Response with whitespace")  # stripped
    end

    it "joins multiple messages with newlines in the user content" do
      # Arrange
      client = CapturingClient.new("Summary")
      squishifier = Mantle::Squishifiers.build_basic_summarizer(client)

      test_messages = [
        "Message 1",
        "Message 2",
        "Message 3"
      ]

      # Act
      squishifier.call(test_messages)

      # Assert
      messages = client.captured_messages.not_nil!
      user_content = messages[1]["content"]

      user_content.should eq("Message 1\nMessage 2\nMessage 3")
    end

    it "handles empty message arrays gracefully" do
      # Arrange
      client = CapturingClient.new("Empty summary")
      squishifier = Mantle::Squishifiers.build_basic_summarizer(client)

      # Act
      result = squishifier.call([] of String)

      # Assert
      result.should eq("Empty summary")
      messages = client.captured_messages.not_nil!
      messages[1]["content"].should eq("")  # Empty user content
    end

    it "handles single message arrays" do
      # Arrange
      client = CapturingClient.new("Single message summary")
      squishifier = Mantle::Squishifiers.build_basic_summarizer(client)

      # Act
      result = squishifier.call(["[User] Only one message"])

      # Assert
      result.should eq("Single message summary")
      messages = client.captured_messages.not_nil!
      messages[1]["content"].should eq("[User] Only one message")
    end

    it "passes through any client exceptions" do
      # Arrange
      failing_client = FailingClient.new
      squishifier = Mantle::Squishifiers.build_basic_summarizer(failing_client)

      # Act & Assert
      expect_raises(Exception, "LLM service unavailable") do
        squishifier.call(["Test message"])
      end
    end

    it "creates independent procs for different clients" do
      # Arrange
      client1 = CapturingClient.new("Response 1")
      client2 = CapturingClient.new("Response 2")

      squishifier1 = Mantle::Squishifiers.build_basic_summarizer(client1)
      squishifier2 = Mantle::Squishifiers.build_basic_summarizer(client2)

      # Act
      result1 = squishifier1.call(["Message A"])
      result2 = squishifier2.call(["Message B"])

      # Assert
      result1.should eq("Response 1")
      result2.should eq("Response 2")

      client1.captured_messages.not_nil![1]["content"].should eq("Message A")
      client2.captured_messages.not_nil![1]["content"].should eq("Message B")
    end
  end
end
