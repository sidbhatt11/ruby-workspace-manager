# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::Workspace do
  describe ".find" do
    it "finds workspace root by .rwm/ directory" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir)
        workspace = described_class.find(dir)
        expect(workspace.root).to eq(dir)
      end
    end

    it "walks up parent directories to find root" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir)
        nested = File.join(dir, "libs", "some_lib")
        FileUtils.mkdir_p(nested)

        workspace = described_class.find(nested)
        expect(workspace.root).to eq(dir)
      end
    end

    it "raises WorkspaceNotFoundError when no .rwm/ exists" do
      Dir.mktmpdir do |dir|
        expect { described_class.find(dir) }.to raise_error(Rwm::WorkspaceNotFoundError)
      end
    end
  end

  describe "#packages" do
    it "discovers packages in libs/ and apps/" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib },
          api: { type: :app }
        })

        workspace = described_class.find(dir)
        names = workspace.packages.map(&:name)

        expect(names).to contain_exactly("auth", "billing", "api")
      end
    end

    it "ignores directories without a Gemfile" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        FileUtils.mkdir_p(File.join(dir, "libs", "no_gemfile"))

        workspace = described_class.find(dir)
        expect(workspace.packages.map(&:name)).to eq(["auth"])
      end
    end

    it "sets correct types for libs and apps" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          api: { type: :app }
        })

        workspace = described_class.find(dir)
        auth = workspace.packages.find { |p| p.name == "auth" }
        api = workspace.packages.find { |p| p.name == "api" }

        expect(auth.type).to eq(:lib)
        expect(api.type).to eq(:app)
      end
    end

    it "returns empty array when no packages exist" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir)
        workspace = described_class.find(dir)
        expect(workspace.packages).to be_empty
      end
    end
  end

  describe "#find_package" do
    it "finds a package by name" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = described_class.find(dir)

        pkg = workspace.find_package("auth")
        expect(pkg.name).to eq("auth")
      end
    end

    it "raises PackageNotFoundError for unknown packages" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir)
        workspace = described_class.find(dir)

        expect { workspace.find_package("nope") }.to raise_error(Rwm::PackageNotFoundError)
      end
    end
  end
end
