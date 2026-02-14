# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::GitHooks do
  describe "#setup" do
    it "creates pre-push and post-commit hooks" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, ".git"))

        hooks = described_class.new(dir)
        expect(hooks.setup).to be true

        pre_push = File.join(dir, ".git", "hooks", "pre-push")
        post_commit = File.join(dir, ".git", "hooks", "post-commit")

        expect(File.exist?(pre_push)).to be true
        expect(File.exist?(post_commit)).to be true
        expect(File.executable?(pre_push)).to be true
        expect(File.executable?(post_commit)).to be true
      end
    end

    it "pre-push hook runs rwm check" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, ".git"))

        described_class.new(dir).setup

        content = File.read(File.join(dir, ".git", "hooks", "pre-push"))
        expect(content).to include("bundle exec rwm check")
      end
    end

    it "post-commit hook rebuilds graph on Gemfile changes" do
      Dir.mktmpdir do |dir|
        FileUtils.mkdir_p(File.join(dir, ".git"))

        described_class.new(dir).setup

        content = File.read(File.join(dir, ".git", "hooks", "post-commit"))
        expect(content).to include("Gemfile")
        expect(content).to include("bundle exec rwm graph")
        expect(content).to include("git diff-tree")
      end
    end

    it "appends to existing hooks without duplicating" do
      Dir.mktmpdir do |dir|
        hooks_dir = File.join(dir, ".git", "hooks")
        FileUtils.mkdir_p(hooks_dir)
        File.write(File.join(hooks_dir, "pre-push"), "#!/bin/bash\necho 'existing hook'\n")
        File.chmod(0o755, File.join(hooks_dir, "pre-push"))

        described_class.new(dir).setup

        content = File.read(File.join(hooks_dir, "pre-push"))
        expect(content).to include("existing hook")
        expect(content).to include("bundle exec rwm check")

        # Running again should not duplicate
        described_class.new(dir).setup
        content = File.read(File.join(hooks_dir, "pre-push"))
        expect(content.scan("bundle exec rwm").size).to eq(1)
      end
    end

    it "returns false when no .git directory exists" do
      Dir.mktmpdir do |dir|
        hooks = described_class.new(dir)
        expect(hooks.setup).to be false
      end
    end
  end
end
