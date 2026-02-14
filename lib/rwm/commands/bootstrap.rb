# frozen_string_literal: true

module Rwm
  module Commands
    class Bootstrap
      def initialize(argv)
        @argv = argv
      end

      def run
        workspace = Workspace.find

        bootstrap_root(workspace)
        setup_hooks(workspace)

        graph = DependencyGraph.build(workspace)
        bootstrap_packages(workspace, graph)
        save_graph(workspace, graph)
        validate_conventions(workspace, graph)
        update_vscode_workspace(workspace)

        puts
        puts "Bootstrap complete!"
        0
      end

      private

      def bootstrap_root(workspace)
        puts "==> Bootstrapping workspace root..."
        run_bundle_install(workspace.root)
        run_rake_bootstrap(workspace.root)
      end

      def setup_hooks(workspace)
        if File.exist?(File.join(workspace.root, ".overcommit.yml"))
          puts "==> Setting up overcommit..."

          overcommit = Overcommit.new(workspace.root)
          if overcommit.setup
            puts "  Overcommit configured."
          else
            $stderr.puts "  Warning: Could not install overcommit hooks."
            $stderr.puts "  Run `overcommit --install` manually after installing the overcommit gem."
            puts "  Hook scripts and config created (will activate once overcommit is installed)."
          end
        else
          puts "==> Installing git hooks..."
          hooks = GitHooks.new(workspace.root)
          if hooks.setup
            puts "  Git hooks installed."
          else
            $stderr.puts "  Warning: Could not install git hooks (no .git directory found)."
          end
        end
      end

      def bootstrap_packages(workspace, graph)
        packages = workspace.packages
        if packages.empty?
          puts "==> No packages found. Skipping package bootstrap."
          return
        end

        # Step 1: bundle install in all packages (parallel by execution level)
        puts "==> Installing gems in #{packages.size} package(s)..."
        install_runner = TaskRunner.new(graph, packages: packages)
        install_runner.run_command do |pkg|
          ["bundle", "install"]
        end

        unless install_runner.success?
          failed = install_runner.failed_results
          $stderr.puts "Error: bundle install failed in: #{failed.map(&:package_name).join(", ")}"
          exit 1
        end

        # Step 2: rake bootstrap in all packages (parallel by execution level)
        bootstrappable = packages.select(&:has_rakefile?)
        unless bootstrappable.empty?
          puts
          puts "==> Running bootstrap tasks in #{bootstrappable.size} package(s)..."
          bootstrap_runner = TaskRunner.new(graph, packages: bootstrappable)
          bootstrap_runner.run_command do |pkg|
            ["bundle", "exec", "rake", "bootstrap"]
          end

          unless bootstrap_runner.success?
            failed = bootstrap_runner.failed_results
            $stderr.puts "Error: rake bootstrap failed in: #{failed.map(&:package_name).join(", ")}"
            exit 1
          end
        end
      end

      def save_graph(workspace, graph)
        puts
        puts "==> Saving dependency graph..."
        graph.save(workspace.graph_path, workspace.root)
        puts "  Graph saved to .rwm/graph.json (#{graph.packages.size} packages, #{graph.edges.values.flatten.size} edges)"
      end

      def validate_conventions(_workspace, graph)
        puts "==> Validating conventions..."
        checker = ConventionChecker.new(graph)
        violations = checker.check

        if violations.empty?
          puts "  All conventions passed."
        else
          $stderr.puts "Convention violations found:"
          violations.each { |v| $stderr.puts "  - #{v}" }
        end
      end

      def update_vscode_workspace(workspace)
        vscode = VscodeWorkspace.new(workspace.root)
        return unless File.exist?(vscode.file_path)

        vscode.generate(workspace.packages)
      end

      def run_bundle_install(dir)
        return unless File.exist?(File.join(dir, "Gemfile"))

        puts "  bundle install..."
        success = system("bundle", "install", chdir: dir)
        unless success
          $stderr.puts "Error: bundle install failed in #{dir}"
          exit 1
        end
      end

      def run_rake_bootstrap(dir)
        return unless File.exist?(File.join(dir, "Rakefile"))

        # Check if bootstrap task exists before running it
        has_task = system("bundle", "exec", "rake", "-s", "-T", "bootstrap",
                          chdir: dir, out: File::NULL, err: File::NULL)
        return unless has_task

        puts "  rake bootstrap..."
        success = system("bundle", "exec", "rake", "bootstrap", chdir: dir)
        unless success
          $stderr.puts "Error: rake bootstrap failed in #{dir}"
          exit 1
        end
      end
    end
  end
end
