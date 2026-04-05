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
    it "sets BUNDLE_GEMFILE to the package's Gemfile in child processes" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        pkg = workspace.find_package("auth")

        runner = described_class.new(graph, packages: [pkg])
        runner.run_command { |p| ["ruby", "-e", "puts ENV['BUNDLE_GEMFILE']"] }

        expect(runner.success?).to be true
        expected_gemfile = File.join(pkg.path, "Gemfile")
        expect(runner.results.first.output).to include(expected_gemfile)
      end
    end

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

    it "skips transitive dependents on failure" do
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

        expect(auth_result.failed?).to be true
        expect(api_result.dep_skipped?).to be true
        expect(api_result.output).to include("Skipped due to failed dependency: auth")
      end
    end

    it "produces :errored result without deadlock on unexpected exception" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command { |_pkg| raise Errno::ENOENT, "no such file" }

        expect(runner.results.size).to eq(1)
        result = runner.results.first
        expect(result.errored?).to be true
        expect(result.output).to include("Errno::ENOENT")
        expect(runner.success?).to be false
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

    it "starts a package as soon as its deps finish (diamond graph)" do
      Dir.mktmpdir do |dir|
        # Diamond: A -> B, A -> C, B -> D, C -> D
        # D has no deps, B and C depend on D, A depends on B and C
        create_fixture_workspace(dir, packages: {
          pkg_a: { type: :app, deps: [:pkg_b, :pkg_c] },
          pkg_b: { type: :lib, deps: [:pkg_d] },
          pkg_c: { type: :lib, deps: [:pkg_d] },
          pkg_d: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        timestamps = {}
        mutex = Mutex.new

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command do |pkg|
          mutex.synchronize { timestamps["#{pkg.name}_start"] = Time.now }
          sleep_time = pkg.name == "pkg_d" ? 0.3 : 0.1
          ["ruby", "-e", "sleep #{sleep_time}; puts '#{pkg.name} done'"]
        end

        expect(runner.success?).to be true

        # D runs first, then B and C can start in parallel, then A
        # B and C should start after D finishes
        expect(timestamps["pkg_b_start"]).to be >= timestamps["pkg_d_start"]
        expect(timestamps["pkg_c_start"]).to be >= timestamps["pkg_d_start"]
        # A should start after both B and C
        expect(timestamps["pkg_a_start"]).to be >= timestamps["pkg_b_start"]
        expect(timestamps["pkg_a_start"]).to be >= timestamps["pkg_c_start"]
      end
    end

    it "respects concurrency limit" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        # With concurrency: 1, packages run sequentially
        start_time = Time.now
        runner = described_class.new(graph, packages: workspace.packages, concurrency: 1)
        runner.run_command { |_pkg| ["ruby", "-e", "sleep 0.3; puts 'done'"] }
        elapsed = Time.now - start_time

        expect(runner.success?).to be true
        # Sequential: ~0.6s; parallel would be ~0.3s
        expect(elapsed).to be >= 0.5
      end
    end

    it "skips only transitive dependents on failure, not unrelated packages" do
      Dir.mktmpdir do |dir|
        # auth (fails) -> api (should be skipped)
        # billing (independent, should still run)
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          api: { type: :app, deps: [:auth] },
          billing: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_command do |pkg|
          if pkg.name == "auth"
            ["ruby", "-e", "exit 1"]
          else
            ["ruby", "-e", "puts 'ran #{pkg.name}'"]
          end
        end

        auth_result = runner.results.find { |r| r.package_name == "auth" }
        api_result = runner.results.find { |r| r.package_name == "api" }
        billing_result = runner.results.find { |r| r.package_name == "billing" }

        expect(auth_result.failed?).to be true
        expect(api_result.dep_skipped?).to be true
        expect(api_result.output).to include("Skipped due to failed dependency: auth")
        expect(billing_result.passed?).to be true
        expect(billing_result.output).to include("ran billing")
      end
    end
  end

  describe "task not found handling" do
    describe "NO_TASK_PATTERN" do
      it "matches case-insensitive variants of the error message" do
        pattern = Rwm::TaskRunner::NO_TASK_PATTERN
        expect("Don't know how to build task 'foo'").to match(pattern)
        expect("don't know how to build task 'foo'").to match(pattern)
        expect("DON'T KNOW HOW TO BUILD TASK 'foo'").to match(pattern)
        # Handles apostrophe variants (don.t matches any single char)
        expect("Don\u2019t know how to build task 'foo'").to match(pattern)
      end

      it "matches the rake --tasks hint text" do
        pattern = Rwm::TaskRunner::NO_TASK_PATTERN
        expect("See rake --tasks for available tasks").to match(pattern)
        expect("Run rake --tasks to see available tasks").to match(pattern)
      end

      it "does not match normal task failure messages" do
        pattern = Rwm::TaskRunner::NO_TASK_PATTERN
        expect("rake aborted!").not_to match(pattern)
        expect("Task failed with exit code 1").not_to match(pattern)
        expect("Error: compilation failed").not_to match(pattern)
      end
    end

    it "treats missing rake task as skipped, not failed" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib, rakefile_content: "# no tasks defined" }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages)
        runner.run_task("nonexistent_task")

        expect(runner.success?).to be true
        result = runner.results.first
        expect(result.skipped?).to be true
      end
    end
  end

  describe "subset package execution" do
    it "skips dependency checks for packages not in run set" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib },
          billing: { type: :lib, deps: [:auth] }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        # Only run billing (not auth), so auth dep is outside run set
        billing = workspace.find_package("billing")
        runner = described_class.new(graph, packages: [billing])
        runner.run_command { |_pkg| ["ruby", "-e", "puts 'done'"] }

        expect(runner.success?).to be true
        expect(runner.results.size).to eq(1)
        expect(runner.results.first.package_name).to eq("billing")
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

    it "handles empty output in buffered mode" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        output = StringIO.new
        $stdout = output

        runner = described_class.new(graph, packages: workspace.packages, buffered: true)
        runner.run_command { |_pkg| ["ruby", "-e", ""] }

        $stdout = STDOUT

        expect(output.string).to include("==> [auth]")
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

  describe "interrupt handling" do
    it "sets @interrupted flag when SIGINT is received" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        runner = described_class.new(graph, packages: workspace.packages, concurrency: 1)

        # Send SIGINT after a brief delay to interrupt the runner
        Thread.new do
          sleep 0.2
          Process.kill("INT", Process.pid)
        end

        expect {
          runner.run_command { |_pkg| ["ruby", "-e", "sleep 2"] }
        }.to raise_error(Interrupt)
      end
    end

    it "restores the previous signal handler after run" do
      Dir.mktmpdir do |dir|
        create_fixture_workspace(dir, packages: {
          auth: { type: :lib }
        })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)

        # Capture handler before run
        handler_before = Signal.trap("INT", "DEFAULT")
        Signal.trap("INT", handler_before)

        runner = described_class.new(graph, packages: workspace.packages)
        $stdout = StringIO.new
        runner.run_command { |_pkg| ["ruby", "-e", "puts 'done'"] }
        $stdout = STDOUT

        # Capture handler after run
        handler_after = Signal.trap("INT", "DEFAULT")
        Signal.trap("INT", handler_after)

        # Handler should be the same as before the run
        expect(handler_after).to eq(handler_before)
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
