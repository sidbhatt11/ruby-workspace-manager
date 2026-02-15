# frozen_string_literal: true

require "optparse"

module Rwm
  module Commands
    class Run
      def initialize(argv)
        @argv = argv
        @affected_only = false
        @committed_only = false
        @no_cache = false
        @buffered = false
        @concurrency = nil
        @dry_run = false
        @base_branch = nil
        parse_options
      end

      def run
        task = @argv.shift

        unless task
          $stderr.puts "Usage: rwm run <task> [<package>] [--affected] [--base REF] [--dry-run] [--no-cache] [--buffered] [--concurrency N]"
          return 1
        end

        package_name = @argv.shift

        workspace = Workspace.find
        graph = DependencyGraph.load(workspace)

        packages = if package_name
                     [workspace.find_package(package_name)]
                   elsif @affected_only
                     detector = AffectedDetector.new(workspace, graph, committed_only: @committed_only, base_branch: @base_branch)
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

        # Filter to packages with a Rakefile (skip those without one entirely)
        runnable = packages.select(&:has_rakefile?)
        if runnable.empty?
          puts "No packages with a Rakefile found."
          return 0
        end

        Rwm.debug("run: #{runnable.size} package(s) with Rakefiles")

        # Auto-detect cacheable tasks unless --no-cache
        cache = TaskCache.new(workspace, graph) unless @no_cache
        if cache
          cacheable, not_cacheable = runnable.partition { |pkg| cache.cacheable?(pkg, task) }
          cached, uncached = cacheable.partition { |pkg| cache.cached?(pkg, task) }
          cached.each { |pkg| puts "[#{pkg.name}] cached" }
          runnable = uncached + not_cacheable
        end

        if runnable.empty?
          puts "All packages cached. Nothing to run."
          return 0
        end

        if @dry_run
          puts "Dry run: would run `rake #{task}` on #{runnable.size} package(s):"
          runnable.each { |pkg| puts "  #{pkg.name}" }
          return 0
        end

        puts "Running `rake #{task}` across #{runnable.size} package(s)..."
        puts

        runner_opts = { packages: runnable, buffered: @buffered }
        runner_opts[:concurrency] = @concurrency if @concurrency
        runner = TaskRunner.new(graph, **runner_opts)
        runner.run_task(task)

        # Store cache for successful cacheable packages
        if cache
          runner.results.each do |result|
            next unless result.success
            next if result.skipped

            pkg = workspace.find_package(result.package_name)
            cache.store(pkg, task) if cache.cacheable?(pkg, task)
          end
        end

        passed, rest = runner.results.partition { |r| r.success && !r.skipped }
        failed, skipped = rest.partition { |r| !r.success }
        skipped_from_rest = runner.results.select(&:skipped)

        total = runner.results.size
        parts = []
        parts << "#{passed.size} passed" unless passed.empty?
        parts << "#{failed.size} failed" unless failed.empty?
        parts << "#{skipped_from_rest.size} skipped" unless skipped_from_rest.empty?

        puts
        puts "#{total} package(s): #{parts.join(", ")}."

        Rwm.debug("passed: #{passed.map(&:package_name).join(", ")}") unless passed.empty?
        Rwm.debug("skipped (no matching task): #{skipped_from_rest.map(&:package_name).join(", ")}") unless skipped_from_rest.empty?

        if failed.empty?
          0
        else
          $stderr.puts "Failed:"
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
          opts.on("--base REF", "Compare against REF instead of auto-detected base branch (with --affected)") do |ref|
            @base_branch = ref
          end
          opts.on("--dry-run", "Show what would run without executing") do
            @dry_run = true
          end
          opts.on("--no-cache", "Bypass task caching even for cacheable tasks") do
            @no_cache = true
          end
          opts.on("--buffered", "Buffer output per-package and print on completion") do
            @buffered = true
          end
          opts.on("--concurrency N", Integer, "Max parallel workers (default: processor count)") do |n|
            @concurrency = n
          end
        end

        parser.order!(@argv)
      end
    end
  end
end
