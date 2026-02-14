# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::TaskRunner do
  def build_graph_with_packages(packages_hash)
    graph = Rwm::DependencyGraph.new
    packages = {}

    packages_hash.each do |name, opts|
      type = opts[:type] || :lib
      path = opts[:path]
      pkg = Rwm::Package.new(name: name.to_s, path: path, type: type)
      graph.add_package(pkg)
      packages[name] = pkg
    end

    (packages_hash.each do |name, opts|
      (opts[:deps] || []).each do |dep|
        graph.add_edge(name.to_s, dep.to_s)
      end
    end)

    [graph, packages]
  end

  describe "#run_command" do
    it "runs a command in each package" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command { |pkg| ["ruby", "-e", "puts 'hello from #{pkg.name}'"] }

        expect(runner.results.size).to eq(2)
        expect(runner.success?).to be true
        expect(runner.results.map(&:package_name)).to contain_exactly("auth", "billing")
      end
    end

    it "prefixes output with package name" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command { |_pkg| ["ruby", "-e", "puts 'test output'"] }

        expect(runner.results.first.output).to include("[auth]")
        expect(runner.results.first.output).to include("test output")
      end
    end

    it "reports failure for failed commands" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command { |_pkg| ["ruby", "-e", "exit 1"] }

        expect(runner.success?).to be false
        expect(runner.failed_results.size).to eq(1)
        expect(runner.failed_results.first.package_name).to eq("auth")
      end
    end

    it "skips downstream levels on failure" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          api: { type: :app, deps: [:auth] }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command do |pkg|
          if pkg.name == "auth"
            ["ruby", "-e", "exit 1"]
          else
            ["ruby", "-e", "puts 'should not run'"]
          end
        end

        expect(runner.results.size).to eq(2)
        auth_result = runner.results.find { |r| r.package_name == "auth" }
        api_result = runner.results.find { |r| r.package_name == "api" }

        expect(auth_result.success).to be false
        expect(api_result.success).to be false
        expect(api_result.output).to include("Skipped")
      end
    end

    it "runs independent packages in parallel" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        # Both packages are at level 0 (no deps), so they run in parallel
        start_time = Time.now
        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command { |_pkg| ["ruby", "-e", "sleep 0.5; puts 'done'"] }
        elapsed = Time.now - start_time

        expect(runner.success?).to be true
        # If run in parallel, should take ~0.5s; if sequential, ~1.0s
        expect(elapsed).to be < 0.8
      end
    end
  end

  describe "buffered output" do
    it "prints output with header when buffered: true" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        output = StringIO.new
        $stdout = output

        runner = described_class.new(graph, packages: workspace.packages, buffered: true)
        runner.run_command { |_pkg| ["ruby", "-e", "puts 'hello'"] }

        $stdout = STDOUT

        expect(output.string).to include("==> [auth]")
        expect(output.string).to include("hello")
        expect(runner.success?).to be true
      end
    end

    it "prints failures to stderr when buffered" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        stderr_output = StringIO.new
        $stderr = stderr_output
        # Suppress stdout
        $stdout = StringIO.new

        runner = described_class.new(graph, packages: workspace.packages, buffered: true)
        runner.run_command { |_pkg| ["ruby", "-e", "$stderr.puts 'error'; exit 1"] }

        $stderr = STDERR
        $stdout = STDOUT

        expect(stderr_output.string).to include("==> [auth]")
        expect(runner.success?).to be false
      end
    end
  end

  describe "#run_task" do
    it "runs a rake task in each package" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_task("ping")

        expect(runner.success?).to be true
        expect(runner.results.first.output).to include("pong")
      end
    end
  end
end
