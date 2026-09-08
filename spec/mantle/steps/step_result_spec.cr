require "../../spec_helper"

describe Mantle::StepResult do
  describe "ok? and err?" do
    it "identifies successful outcomes without error" do
      result = Mantle::StepResult(String, Mantle::StepError).ok("hello")
      result.ok?.should be_true
      result.err?.should be_false
      result.value.should eq("hello")
      result.error.should be_nil
    end

    it "identifies failure outcomes with error" do
      result = Mantle::StepResult(String, Mantle::StepError).error(Mantle::StepError::ClientFailure)
      result.ok?.should be_false
      result.err?.should be_true
      result.value.should be_nil
      result.error.should eq(Mantle::StepError::ClientFailure)
    end
  end

  describe "#unwrap" do
    it "returns the unwrapped value when successful" do
      result = Mantle::StepResult(String, Mantle::StepError).ok("verified payload")
      result.unwrap.should eq("verified payload")
    end

    it "raises StepUnwrapError when result contains an error" do
      result = Mantle::StepResult(String, Mantle::StepError).error(Mantle::StepError::MaxIterationsReached)
      expect_raises(Mantle::StepUnwrapError, /MaxIterationsReached/) do
        result.unwrap
      end
    end

    it "raises StepUnwrapError when successful result has nil value" do
      result = Mantle::StepResult(String, Mantle::StepError).new
      expect_raises(Mantle::StepUnwrapError, /nil value/) do
        result.unwrap
      end
    end
  end

  describe "metadata tracking" do
    it "persists thinking, iterations, and raw_response" do
      raw_resp = Mantle::Clients::Response.new(content: "res", tool_calls: nil, thinking: "deep thoughts")
      result = Mantle::StepResult(String, Mantle::StepError).new(
        value: "res",
        thinking: "deep thoughts",
        iterations: 3,
        raw_response: raw_resp
      )

      result.thinking.should eq("deep thoughts")
      result.iterations.should eq(3)
      result.raw_response.should eq(raw_resp)
    end
  end

  describe "convenience factory methods" do
    it "creates ok results with untyped factory" do
      result = Mantle::StepResult.ok("auto typed")
      result.should be_a(Mantle::StepResult(String, Mantle::StepError))
      result.ok?.should be_true
      result.value.should eq("auto typed")
    end

    it "creates error results with untyped factory" do
      result = Mantle::StepResult.error(Mantle::StepError::ToolExecutionFailure)
      result.should be_a(Mantle::StepResult(String, Mantle::StepError))
      result.err?.should be_true
      result.error.should eq(Mantle::StepError::ToolExecutionFailure)
    end
  end
end
