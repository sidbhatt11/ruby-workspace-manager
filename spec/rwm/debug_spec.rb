# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Rwm debug logging" do
  after { Rwm.verbose = false }

  describe ".verbose?" do
    it "defaults to false" do
      Rwm.verbose = false
      expect(Rwm.verbose?).to be false
    end

    it "returns true when set" do
      Rwm.verbose = true
      expect(Rwm.verbose?).to be true
    end
  end

  describe ".debug" do
    it "prints to stderr when verbose" do
      Rwm.verbose = true
      expect { Rwm.debug("test message") }.to output(/\[rwm debug\] test message/).to_stderr
    end

    it "does not print when not verbose" do
      Rwm.verbose = false
      expect { Rwm.debug("test message") }.not_to output.to_stderr
    end
  end
end
