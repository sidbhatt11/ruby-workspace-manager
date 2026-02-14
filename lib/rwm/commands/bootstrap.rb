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
        setup_overcommit(workspace)
        bootstrap_packages(workspace)
        build_graph(workspace)

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

      def setup_overcommit(workspace)
        puts "==> Setting up overcommit..."

        overcommit = Overcommit.new(workspace.root)
        if overcommit.setup
          puts "  Overcommit configured."
        else
          $stderr.puts "  Warning: Could not install overcommit hooks."
          $stderr.puts "  Run `overcommit --install` manually after installing the overcommit gem."
          puts "  Hook scripts and config created (will activate once overcommit is installed)."
        end
      end

      def bootstrap_packages(workspace)
        packages = workspace.packages
        if packages.empty?
          puts "==> No packages found. Skipping package bootstrap."
          return
        end

        graph = DependencyGraph.build(workspace)

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

      def build_graph(workspace)
        puts
        puts "==> Building dependency graph..."
        require "rwm/commands/graph"
        Commands::Graph.new([]).run

        puts "==> Validating conventions..."
        require "rwm/commands/check"
        Commands::Check.new([]).run
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
