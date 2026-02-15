# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::GemfileParser do
  describe ".parse" do
    it "extracts path dependencies that match known packages" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib, deps: [:auth] }
        })

        workspace = Rwm::Workspace.find(dir)
        billing = workspace.find_package("billing")

        deps = described_class.parse(billing.gemfile_path, workspace.packages)
        expect(deps.map(&:name)).to eq(["auth"])
      end
    end

    it "returns empty array when no path deps exist" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        auth = workspace.find_package("auth")

        deps = described_class.parse(auth.gemfile_path, workspace.packages)
        expect(deps).to be_empty
      end
    end

    it "skips non-path source dependencies" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        # Add a rubygems (non-path) dependency
        gemfile_path = File.join(dir, "libs", "auth", "Gemfile")
        File.write(gemfile_path, <<~GEMFILE)
          source "https://rubygems.org"
          gemspec
          gem "rake"
        GEMFILE

        workspace = Rwm::Workspace.find(dir)
        auth = workspace.find_package("auth")

        deps = described_class.parse(auth.gemfile_path, workspace.packages)
        expect(deps).to be_empty
      end
    end

    it "ignores path deps that don't match known packages" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        # Add a path dep to an unknown package
        gemfile_path = File.join(dir, "libs", "auth", "Gemfile")
        File.write(gemfile_path, <<~GEMFILE)
          source "https://rubygems.org"
          gemspec
          gem "unknown", path: "../unknown"
        GEMFILE

        workspace = Rwm::Workspace.find(dir)
        auth = workspace.find_package("auth")

        deps = described_class.parse(auth.gemfile_path, workspace.packages)
        expect(deps).to be_empty
      end
    end
  end
end
