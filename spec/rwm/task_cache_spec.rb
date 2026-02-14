# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::TaskCache do
  describe "#content_hash" do
    it "produces a deterministic hash for the same content" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        pkg = workspace.find_package("auth")

        cache = described_class.new(workspace, graph)
        hash1 = cache.content_hash(pkg)
        hash2 = cache.content_hash(pkg)

        expect(hash1).to eq(hash2)
        expect(hash1).to match(/\A[0-9a-f]{64}\z/) # SHA256 hex
      end
    end

    it "changes when a source file changes" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        pkg = workspace.find_package("auth")

        hash_before = described_class.new(workspace, graph).content_hash(pkg)

        File.write(File.join(pkg.path, "lib", "auth.rb"), "module Auth; end # changed")

        hash_after = described_class.new(workspace, graph).content_hash(pkg)

        expect(hash_before).not_to eq(hash_after)
      end
    end

    it "changes when a dependency's source changes" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib, deps: [:auth] }
        })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        billing = workspace.find_package("billing")
        hash_before = described_class.new(workspace, graph).content_hash(billing)

        # Change auth (a dependency of billing)
        auth = workspace.find_package("auth")
        File.write(File.join(auth.path, "lib", "auth.rb"), "module Auth; end # changed")

        hash_after = described_class.new(workspace, graph).content_hash(billing)

        expect(hash_before).not_to eq(hash_after)
      end
    end

    it "differs between packages with different content" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib }
        })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        auth_hash = described_class.new(workspace, graph).content_hash(workspace.find_package("auth"))
        billing_hash = described_class.new(workspace, graph).content_hash(workspace.find_package("billing"))

        expect(auth_hash).not_to eq(billing_hash)
      end
    end
  end

  describe "#cached? and #store" do
    it "returns false when nothing is cached" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        expect(cache.cached?(pkg, "test")).to be false
      end
    end

    it "returns true after storing a successful run" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        cache.store(pkg, "test")

        expect(cache.cached?(pkg, "test")).to be true
      end
    end

    it "invalidates when source changes after storing" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        pkg = workspace.find_package("auth")

        cache1 = described_class.new(workspace, graph)
        cache1.store(pkg, "test")

        # Change a file
        File.write(File.join(pkg.path, "lib", "auth.rb"), "module Auth; end # changed")

        # New cache instance (fresh hashes)
        cache2 = described_class.new(workspace, graph)
        expect(cache2.cached?(pkg, "test")).to be false
      end
    end

    it "caches different tasks independently" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        cache.store(pkg, "test")

        expect(cache.cached?(pkg, "test")).to be true
        expect(cache.cached?(pkg, "build")).to be false
      end
    end

    it "invalidates dependents when a dependency changes" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib, deps: [:auth] }
        })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        auth = workspace.find_package("auth")
        billing = workspace.find_package("billing")

        cache1 = described_class.new(workspace, graph)
        cache1.store(auth, "test")
        cache1.store(billing, "test")

        expect(cache1.cached?(billing, "test")).to be true

        # Change auth
        File.write(File.join(auth.path, "lib", "auth.rb"), "module Auth; end # changed")

        cache2 = described_class.new(workspace, graph)
        expect(cache2.cached?(auth, "test")).to be false
        expect(cache2.cached?(billing, "test")).to be false
      end
    end

    it "stores cache files in .rwm/cache/" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        cache.store(pkg, "test")

        cache_file = File.join(dir, ".rwm", "cache", "auth-test")
        expect(File.exist?(cache_file)).to be true
        expect(File.read(cache_file)).to match(/\A[0-9a-f]{64}\z/)
      end
    end
  end

  describe "#outputs_exist?" do
    it "returns true when output files match the pattern" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        # Create an output file matching the pattern
        FileUtils.mkdir_p(File.join(pkg.path, "pkg"))
        File.write(File.join(pkg.path, "pkg", "auth-0.1.0.gem"), "fake gem")

        expect(cache.outputs_exist?(pkg, "pkg/*.gem")).to be true
      end
    end

    it "returns false when no output files match" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        expect(cache.outputs_exist?(pkg, "pkg/*.gem")).to be false
      end
    end
  end

  describe "#cached? with output verification" do
    it "invalidates when declared outputs are missing" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        # Store the cache
        cache.store(pkg, "build")

        # Stub cache_declarations to return output pattern
        allow(cache).to receive(:cache_declarations).with(pkg).and_return({
          "build" => { "output" => "pkg/*.gem" }
        })

        # No output files exist → should be false
        expect(cache.cached?(pkg, "build")).to be false
      end
    end

    it "returns true when declared outputs exist" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        # Store the cache
        cache.store(pkg, "build")

        # Create output files
        FileUtils.mkdir_p(File.join(pkg.path, "pkg"))
        File.write(File.join(pkg.path, "pkg", "auth-0.1.0.gem"), "fake gem")

        # Stub cache_declarations to return output pattern
        allow(cache).to receive(:cache_declarations).with(pkg).and_return({
          "build" => { "output" => "pkg/*.gem" }
        })

        expect(cache.cached?(pkg, "build")).to be true
      end
    end
  end

  describe "#content_hash with missing dependency" do
    it "raises PackageNotFoundError when a dependency is missing" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib, deps: [:auth] }
        })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        # Delete the auth package directory after building the graph
        FileUtils.rm_rf(File.join(dir, "libs", "auth"))

        # Force a fresh workspace that won't find auth
        fresh_workspace = Rwm::Workspace.find(dir)
        cache = described_class.new(fresh_workspace, graph)
        billing = fresh_workspace.find_package("billing")

        expect { cache.content_hash(billing) }.to raise_error(Rwm::PackageNotFoundError)
      end
    end
  end

  describe "#cacheable?" do
    it "returns true for tasks declared via cache_declarations" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: { auth: { type: :lib } })
        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        cache = described_class.new(workspace, graph)
        pkg = workspace.find_package("auth")

        allow(cache).to receive(:cache_declarations).with(pkg).and_return({
          "spec" => { "output" => nil }
        })

        expect(cache.cacheable?(pkg, "spec")).to be true
        expect(cache.cacheable?(pkg, "bootstrap")).to be false
      end
    end
  end
end
