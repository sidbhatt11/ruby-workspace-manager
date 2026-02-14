# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::CLI do
  describe ".run" do
    it "prints version with --version" do
      expect { described_class.run(["--version"]) }.to output(/rwm #{Rwm::VERSION}/).to_stdout
    end

    it "prints help with --help" do
      expect { described_class.run(["--help"]) }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "prints help with no arguments" do
      expect { described_class.run([]) }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "returns 1 for unknown commands" do
      result = nil
      expect { result = described_class.run(["nonexistent"]) }.to output(/Unknown command/).to_stderr
      expect(result).to eq(1)
    end
  end
end
