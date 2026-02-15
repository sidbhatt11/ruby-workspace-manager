# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::CLI do
  describe ".run" do
    it "prints version via --version, -v, and version command" do
      %w[--version -v version].each do |arg|
        expect { described_class.run([arg]) }.to output(/rwm #{Rwm::VERSION}/).to_stdout
      end
    end

    it "prints help via --help, -h, help command, and no arguments" do
      [["--help"], ["-h"], ["help"], []].each do |args|
        expect { described_class.run(args) }.to output(/Ruby Workspace Manager/).to_stdout
      end
    end

    it "help text includes key commands and flags" do
      output = StringIO.new
      $stdout = output
      described_class.run(["--help"])
      $stdout = STDOUT
      text = output.string

      %w[--verbose --dry-run --base\ REF cache\ clean version].each do |expected|
        expect(text).to include(expected), "expected help text to include #{expected.inspect}"
      end
    end

    it "forwards unknown commands as tasks to run" do
      fake_cmd = double("cmd", run: 0)
      fake_class = double("class")
      allow(fake_class).to receive(:new).with(["lint"]).and_return(fake_cmd)
      stub_const("Rwm::Commands::Run", fake_class)

      cli = described_class.new(["lint"])
      allow(cli).to receive(:check_required_tools)
      allow(cli).to receive(:require).with("rwm/commands/run")

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

    it "does not check tools for help or version" do
      %w[--help --version].each do |flag|
        cli = described_class.new([flag])
        expect(cli).not_to receive(:check_required_tools)
        expect { cli.run }.to output.to_stdout
      end
    end

    it "registers the cache command" do
      expect(Rwm::CLI::COMMANDS).to include("cache" => "Commands::Cache")
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
