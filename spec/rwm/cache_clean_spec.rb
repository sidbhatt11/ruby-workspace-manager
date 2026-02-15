# frozen_string_literal: true

require "spec_helper"

RSpec.describe "TaskCache.clean" do
  describe ".clean" do
    it "removes all cache files" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib }
        })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        cache = Rwm::TaskCache.new(workspace, graph)
        cache.store(workspace.find_package("auth"), "test")
        cache.store(workspace.find_package("billing"), "test")

        cache_dir = File.join(dir, ".rwm", "cache")
        expect(Dir.glob(File.join(cache_dir, "*")).size).to eq(2)

        Rwm::TaskCache.clean(workspace)
        expect(Dir.glob(File.join(cache_dir, "*")).size).to eq(0)
      end
    end

    it "removes cache files for a specific package" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib }
        })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        cache = Rwm::TaskCache.new(workspace, graph)
        cache.store(workspace.find_package("auth"), "test")
        cache.store(workspace.find_package("billing"), "test")

        Rwm::TaskCache.clean(workspace, package_name: "auth")

        cache_dir = File.join(dir, ".rwm", "cache")
        remaining = Dir.glob(File.join(cache_dir, "*")).map { |f| File.basename(f) }
        expect(remaining).to eq(["billing-test"])
      end
    end

    it "does nothing when cache directory does not exist" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)

        expect { Rwm::TaskCache.clean(workspace) }.not_to raise_error
      end
    end
  end
end
