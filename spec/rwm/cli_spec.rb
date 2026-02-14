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

    it "exits with error when git is not available" do
      cli = described_class.new(["list"])
      allow(cli).to receive(:system).with("which", "git", out: File::NULL, err: File::NULL).and_return(false)

      expect { cli.run }.to output(/git is not installed/).to_stderr.and raise_error(SystemExit)
    end

    it "exits with error when bundle is not available" do
      cli = described_class.new(["list"])
      allow(cli).to receive(:system).with("which", "git", out: File::NULL, err: File::NULL).and_return(true)
      allow(cli).to receive(:system).with("which", "bundle", out: File::NULL, err: File::NULL).and_return(false)

      expect { cli.run }.to output(/bundle is not installed/).to_stderr.and raise_error(SystemExit)
    end

    it "does not check tools for help" do
      cli = described_class.new(["--help"])
      expect(cli).not_to receive(:check_required_tools)
      expect { cli.run }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "does not check tools for version" do
      cli = described_class.new(["--version"])
      expect(cli).not_to receive(:check_required_tools)
      expect { cli.run }.to output(/rwm/).to_stdout
    end

    it "recognizes task shortcuts" do
      expect(Rwm::CLI::TASK_SHORTCUTS).to include("test", "spec", "build")
    end
  end
end
