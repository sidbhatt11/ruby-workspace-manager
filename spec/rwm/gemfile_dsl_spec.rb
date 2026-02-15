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

  describe "transitive resolution" do
    let(:tmpdir) { Dir.mktmpdir("rwm-gemfile-dsl") }
    let(:root) { tmpdir }

    before do
      allow(dsl).to receive(:rwm_workspace_root).and_return(root)
      allow(dsl).to receive(:gem)
    end

    after do
      FileUtils.rm_rf(tmpdir)
      Rwm.resolved_libs.clear
    end

    def write_lib_gemfile(name, content)
      lib_dir = File.join(root, "libs", name)
      FileUtils.mkdir_p(lib_dir)
      File.write(File.join(lib_dir, "Gemfile"), content)
    end

    it "adds transitive deps from target Gemfile" do
      write_lib_gemfile("core", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
        gem "core", path: "../../libs/core"
      GEMFILE

      dsl.rwm_lib("auth")

      expect(dsl).to have_received(:gem).with("auth", path: File.join(root, "libs", "auth"))
      expect(dsl).to have_received(:gem).with("core", path: File.join(root, "libs", "core"))
    end

    it "handles diamond deps without duplicates" do
      write_lib_gemfile("core", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
        gem "core", path: "../../libs/core"
      GEMFILE

      write_lib_gemfile("billing", <<~GEMFILE)
        source "https://rubygems.org"
        gem "core", path: "../../libs/core"
      GEMFILE

      dsl.rwm_lib("auth")
      dsl.rwm_lib("billing")

      expect(dsl).to have_received(:gem).with("core", path: File.join(root, "libs", "core")).once
    end

    it "does not resolve same lib twice" do
      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      dsl.rwm_lib("auth")
      dsl.rwm_lib("auth")

      expect(dsl).to have_received(:gem).with("auth", path: File.join(root, "libs", "auth")).once
    end

    it "skips commented-out rwm_lib lines in target Gemfile" do
      write_lib_gemfile("core", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
        # gem "core", path: "../../libs/core"
      GEMFILE

      dsl.rwm_lib("auth")

      expect(dsl).to have_received(:gem).with("auth", path: File.join(root, "libs", "auth"))
      expect(dsl).not_to have_received(:gem).with("core", anything)
    end

    it "resolves deep chains (A -> B -> C)" do
      write_lib_gemfile("base", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      write_lib_gemfile("middle", <<~GEMFILE)
        source "https://rubygems.org"
        gem "base", path: "../../libs/base"
      GEMFILE

      write_lib_gemfile("top", <<~GEMFILE)
        source "https://rubygems.org"
        gem "middle", path: "../../libs/middle"
      GEMFILE

      dsl.rwm_lib("top")

      expect(dsl).to have_received(:gem).with("top", path: File.join(root, "libs", "top"))
      expect(dsl).to have_received(:gem).with("middle", path: File.join(root, "libs", "middle"))
      expect(dsl).to have_received(:gem).with("base", path: File.join(root, "libs", "base"))
    end

    it "handles cycles without infinite recursion" do
      write_lib_gemfile("alpha", <<~GEMFILE)
        source "https://rubygems.org"
        gem "beta", path: "../../libs/beta"
      GEMFILE

      write_lib_gemfile("beta", <<~GEMFILE)
        source "https://rubygems.org"
        gem "alpha", path: "../../libs/alpha"
      GEMFILE

      expect { dsl.rwm_lib("alpha") }.not_to raise_error

      expect(dsl).to have_received(:gem).with("alpha", path: File.join(root, "libs", "alpha")).once
      expect(dsl).to have_received(:gem).with("beta", path: File.join(root, "libs", "beta")).once
    end

    it "does not forward opts to transitive deps" do
      write_lib_gemfile("core", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
        gem "core", path: "../../libs/core"
      GEMFILE

      dsl.rwm_lib("auth", group: :development)

      expect(dsl).to have_received(:gem).with("auth", group: :development, path: File.join(root, "libs", "auth"))
      expect(dsl).to have_received(:gem).with("core", path: File.join(root, "libs", "core"))
    end

    it "ignores non-workspace path deps in target Gemfile" do
      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
        gem "some_external", path: "/opt/external/some_external"
      GEMFILE

      dsl.rwm_lib("auth")

      expect(dsl).to have_received(:gem).with("auth", path: File.join(root, "libs", "auth"))
      expect(dsl).not_to have_received(:gem).with("some_external", anything)
    end

    it "populates Rwm.resolved_libs with all resolved names" do
      write_lib_gemfile("core", <<~GEMFILE)
        source "https://rubygems.org"
      GEMFILE

      write_lib_gemfile("auth", <<~GEMFILE)
        source "https://rubygems.org"
        gem "core", path: "../../libs/core"
      GEMFILE

      dsl.rwm_lib("auth")

      expect(Rwm.resolved_libs).to contain_exactly("auth", "core")
    end
  end

end
