# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::CLI do
  describe ".run" do
    it "prints version with --version" do
      expect { described_class.run(["--version"]) }.to output(/rwm #{Rwm::VERSION}/).to_stdout
    end

    it "prints version with -v" do
      expect { described_class.run(["-v"]) }.to output(/rwm #{Rwm::VERSION}/).to_stdout
    end

    it "prints help with --help" do
      expect { described_class.run(["--help"]) }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "prints help with -h" do
      expect { described_class.run(["-h"]) }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "prints help with help command" do
      expect { described_class.run(["help"]) }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "prints version with version command" do
      expect { described_class.run(["version"]) }.to output(/rwm #{Rwm::VERSION}/).to_stdout
    end

    it "prints help with no arguments" do
      expect { described_class.run([]) }.to output(/Ruby Workspace Manager/).to_stdout
    end

    it "returns 1 for unknown commands" do
      result = nil
      expect { result = described_class.run(["nonexistent"]) }.to output(/Unknown command/).to_stderr
      expect(result).to eq(1)
    end

    it "returns error when git is not available" do
      cli = described_class.new(["list"])
      allow(cli).to receive(:system).with("which", "git", out: File::NULL, err: File::NULL).and_return(false)

      result = nil
      expect { result = cli.run }.to output(/git is not installed/).to_stderr
      expect(result).to eq(1)
    end

    it "returns error when bundle is not available" do
      cli = described_class.new(["list"])
      allow(cli).to receive(:system).with("which", "git", out: File::NULL, err: File::NULL).and_return(true)
      allow(cli).to receive(:system).with("which", "bundle", out: File::NULL, err: File::NULL).and_return(false)

      result = nil
      expect { result = cli.run }.to output(/bundle is not installed/).to_stderr
      expect(result).to eq(1)
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

    it "registers the cache command" do
      expect(Rwm::CLI::COMMANDS).to include("cache" => "Commands::Cache")
    end

    it "includes --verbose in help text" do
      expect { described_class.run(["--help"]) }.to output(/--verbose/).to_stdout
    end

    it "includes cache clean in help text" do
      expect { described_class.run(["--help"]) }.to output(/cache clean/).to_stdout
    end

    it "includes --dry-run in help text" do
      expect { described_class.run(["--help"]) }.to output(/--dry-run/).to_stdout
    end

    it "includes --base in help text" do
      expect { described_class.run(["--help"]) }.to output(/--base REF/).to_stdout
    end

    it "expands task shortcuts to run command" do
      fake_cmd = double("cmd", run: 0)
      fake_class = double("class")
      allow(fake_class).to receive(:new).with(["test"]).and_return(fake_cmd)
      stub_const("Rwm::Commands::Run", fake_class)

      cli = described_class.new(["test"])
      allow(cli).to receive(:check_required_tools)
      allow(cli).to receive(:require).with("rwm/commands/run")
      expect(fake_class).to have_received(:new).with(["test"]).at_most(:once)

      result = cli.run
      expect(result).to eq(0)
    end

    it "dispatches known commands" do
      fake_cmd = double("cmd", run: 0)
      fake_class = double("class")
      allow(fake_class).to receive(:new).with([]).and_return(fake_cmd)
      stub_const("Rwm::Commands::List", fake_class)

      cli = described_class.new(["list"])
      allow(cli).to receive(:check_required_tools)
      allow(cli).to receive(:require).with("rwm/commands/list")

      result = cli.run
      expect(result).to eq(0)
    end
  end

  describe "--verbose flag" do
    after { Rwm.verbose = false }

    it "sets Rwm.verbose when --verbose is passed" do
      cli = described_class.new(["--verbose", "--help"])
      expect { cli.run }.to output.to_stdout
      expect(Rwm.verbose?).to be true
    end

    it "sets Rwm.verbose when RWM_DEBUG=1" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("RWM_DEBUG").and_return("1")
      cli = described_class.new(["--help"])
      expect { cli.run }.to output.to_stdout
      expect(Rwm.verbose?).to be true
    end

    it "strips --verbose from argv before command dispatch" do
      cli = described_class.new(["--verbose", "--version"])
      expect { cli.run }.to output(/rwm #{Rwm::VERSION}/).to_stdout
    end
  end
end
