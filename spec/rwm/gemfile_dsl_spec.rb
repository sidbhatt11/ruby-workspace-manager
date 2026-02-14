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

  describe "#rwm_app" do
    it "calls gem with the correct path under apps/" do
      root = dsl.rwm_workspace_root
      expected_path = File.join(root, "apps", "web")

      expect(dsl).to receive(:gem).with("web", path: expected_path)
      dsl.rwm_app("web")
    end
  end
end
