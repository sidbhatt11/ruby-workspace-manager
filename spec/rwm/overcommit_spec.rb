# frozen_string_literal: true

require "spec_helper"
require "yaml"

RSpec.describe Rwm::Overcommit do
  describe "#setup" do
    it "creates .overcommit.yml with rwm hooks" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        overcommit.setup

        config = YAML.safe_load(File.read(File.join(dir, ".overcommit.yml")))
        expect(config["PrePush"]["CustomScript"]["enabled"]).to be true
        expect(config["PostCommit"]["CustomScript"]["enabled"]).to be true
      end
    end

    it "merges into existing .overcommit.yml without clobbering" do
      Dir.mktmpdir do |dir|
        existing = {
          "PreCommit" => { "RuboCop" => { "enabled" => true } },
          "PostCommit" => { "BundleAudit" => { "enabled" => true } }
        }
        File.write(File.join(dir, ".overcommit.yml"), YAML.dump(existing))

        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        overcommit.setup

        config = YAML.safe_load(File.read(File.join(dir, ".overcommit.yml")))
        # Existing hooks preserved
        expect(config["PreCommit"]["RuboCop"]["enabled"]).to be true
        expect(config["PostCommit"]["BundleAudit"]["enabled"]).to be true
        # RWM hooks added
        expect(config["PrePush"]["CustomScript"]["enabled"]).to be true
        expect(config["PostCommit"]["CustomScript"]["enabled"]).to be true
      end
    end

    it "creates executable hook scripts" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        overcommit.setup

        pre_push = File.join(dir, ".git-hooks", "pre_push", "rwm_check")
        post_commit = File.join(dir, ".git-hooks", "post_commit", "rwm_graph")

        expect(File.exist?(pre_push)).to be true
        expect(File.exist?(post_commit)).to be true
        expect(File.executable?(pre_push)).to be true
        expect(File.executable?(post_commit)).to be true
      end
    end

    it "pre_push script runs rwm check" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        overcommit.setup

        content = File.read(File.join(dir, ".git-hooks", "pre_push", "rwm_check"))
        expect(content).to include("bundle exec rwm check")
      end
    end

    it "post_commit script rebuilds graph only on Gemfile changes" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        overcommit.setup

        content = File.read(File.join(dir, ".git-hooks", "post_commit", "rwm_graph"))
        expect(content).to include("Gemfile")
        expect(content).to include("bundle exec rwm graph")
        expect(content).to include("git diff-tree")
      end
    end

    it "is idempotent — running twice produces the same result" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        overcommit.setup
        first_config = File.read(File.join(dir, ".overcommit.yml"))
        first_script = File.read(File.join(dir, ".git-hooks", "pre_push", "rwm_check"))

        overcommit.setup
        second_config = File.read(File.join(dir, ".overcommit.yml"))
        second_script = File.read(File.join(dir, ".git-hooks", "pre_push", "rwm_check"))

        expect(first_config).to eq(second_config)
        expect(first_script).to eq(second_script)
      end
    end

    it "creates config and scripts even when overcommit install fails" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(false)

        result = overcommit.setup

        expect(result).to be false
        expect(File.exist?(File.join(dir, ".overcommit.yml"))).to be true
        expect(File.exist?(File.join(dir, ".git-hooks", "pre_push", "rwm_check"))).to be true
        expect(File.exist?(File.join(dir, ".git-hooks", "post_commit", "rwm_graph"))).to be true
      end
    end

    it "does not call sign when install fails" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(false)

        overcommit.setup

        # install is called once, sign is NOT called
        expect(overcommit).to have_received(:system).with(
          "bundle", "exec", "overcommit", "--install",
          hash_including(chdir: dir)
        ).once
        expect(overcommit).not_to have_received(:system).with(
          "bundle", "exec", "overcommit", "--sign",
          hash_including(chdir: dir)
        )
      end
    end

    it "returns true when overcommit installs successfully" do
      Dir.mktmpdir do |dir|
        overcommit = described_class.new(dir)
        allow(overcommit).to receive(:system).and_return(true)

        expect(overcommit.setup).to be true
      end
    end
  end
end
