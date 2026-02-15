# frozen_string_literal: true

require "spec_helper"
require "rwm/gemfile"

RSpec.describe Rwm::GemfileDsl do
  let(:dsl) { Bundler::Dsl.new }

  describe "#rwm_workspace_root" do
    it "returns the git root directory" do
      root = dsl.rwm_workspace_root
      expect(root).to be_a(String)
      expect(root).not_to be_empty
      expect(File.directory?(File.join(root, ".git"))).to be true
    end

    it "raises when not inside a git repository" do
      fresh_dsl = Bundler::Dsl.new
      allow(Open3).to receive(:capture3).with("git", "rev-parse", "--show-toplevel")
        .and_return(["", "", instance_double(Process::Status, success?: false)])

      expect { fresh_dsl.rwm_workspace_root }.to raise_error(RuntimeError, /not inside a git repository/)
    end
  end

  describe "#rwm_lib" do
    it "calls gem with the correct path under libs/" do
      root = dsl.rwm_workspace_root
      expected_path = File.join(root, "libs", "auth")

      expect(dsl).to receive(:gem).with("auth", path: expected_path)
      dsl.rwm_lib("auth")
    end

    it "accepts string or symbol names" do
      root = dsl.rwm_workspace_root
      expected_path = File.join(root, "libs", "auth")

      expect(dsl).to receive(:gem).with("auth", path: expected_path)
      dsl.rwm_lib(:auth)
    end

    it "passes extra options through to gem" do
      root = dsl.rwm_workspace_root
      expected_path = File.join(root, "libs", "auth")

      expect(dsl).to receive(:gem).with("auth", group: :development, path: expected_path)
      dsl.rwm_lib("auth", group: :development)
    end
  end

end
