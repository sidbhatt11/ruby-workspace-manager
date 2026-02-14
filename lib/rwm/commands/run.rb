# frozen_string_literal: true

require "optparse"

module Rwm
  module Commands
    class Run
      def initialize(argv)
        @argv = argv
        @affected_only = false
        @committed_only = false
        @use_cache = false
        parse_options
      end

      def run
        task = @argv.shift

        unless task
          $stderr.puts "Usage: rwm run <task> [<package>] [--affected] [--cache]"
          return 1
        end

        package_name = @argv.shift

        workspace = Workspace.find
        graph = DependencyGraph.build(workspace)

        packages = if package_name
                     pkg = workspace.find_package(package_name)
                     unless pkg
                       $stderr.puts "Unknown package: #{package_name}"
                       return 1
                     end
                     [pkg]
                   elsif @affected_only
                     detector = AffectedDetector.new(workspace, graph, committed_only: @committed_only)
                     affected = detector.affected_packages
                     if affected.empty?
                       puts "No affected packages. Nothing to run."
                       return 0
                     end
                     puts "Running on #{affected.size} affected package(s)..."
                     affected
                   else
                     workspace.packages
                   end

        if packages.empty?
          puts "No packages found."
          return 0
        end

        # Filter to packages that have a Rakefile
        runnable = packages.select(&:has_rakefile?)
        if runnable.empty?
          puts "No packages with a Rakefile found."
          return 0
        end

        # Filter out cached packages if --cache is enabled
        cache = TaskCache.new(workspace, graph) if @use_cache
        if cache
          cached, uncached = runnable.partition { |pkg| cache.cached?(pkg, task) }
          cached.each { |pkg| puts "[#{pkg.name}] cached" }
          runnable = uncached
        end

        if runnable.empty?
          puts "All packages cached. Nothing to run."
          return 0
        end

        puts "Running `rake #{task}` across #{runnable.size} package(s)..."
        puts

        runner = TaskRunner.new(graph, packages: runnable)
        runner.run_task(task)

        # Store cache for successful packages
        if cache
          runner.results.each do |result|
            next unless result.success

            pkg = workspace.find_package(result.package_name)
            cache.store(pkg, task)
          end
        end

        puts
        if runner.success?
          puts "All packages passed."
          0
        else
          failed = runner.failed_results
          $stderr.puts "#{failed.size} package(s) failed:"
          failed.each { |r| $stderr.puts "  - #{r.package_name}" }
          1
        end
      end

      private

      def parse_options
        parser = OptionParser.new do |opts|
          opts.on("--affected", "Only run on affected packages") do
            @affected_only = true
          end
          opts.on("--committed", "Only consider committed changes (with --affected)") do
            @committed_only = true
          end
          opts.on("--cache", "Skip packages whose inputs haven't changed") do
            @use_cache = true
          end
        end

        parser.order!(@argv)
      end
    end
  end
end
