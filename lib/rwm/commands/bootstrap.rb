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

        # Install overcommit hooks
        success = system("bundle", "exec", "overcommit", "--install", chdir: workspace.root)
        unless success
          $stderr.puts "Warning: Failed to install overcommit hooks. You may need to run `overcommit --install` manually."
          return
        end

        # TODO: Merge rwm-specific hooks into .overcommit.yml
        puts "  Overcommit hooks installed."
      end

      def bootstrap_packages(workspace)
        packages = workspace.packages
        if packages.empty?
          puts "==> No packages found. Skipping package bootstrap."
          return
        end

        puts "==> Bootstrapping #{packages.size} package(s)..."

        # Sequential for now — will be upgraded to parallel by execution level in Phase 2
        packages.each do |pkg|
          puts
          puts "--- #{pkg.name} (#{pkg.type}) ---"
          run_bundle_install(pkg.path)
          run_rake_bootstrap(pkg.path)
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
