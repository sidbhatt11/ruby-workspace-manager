# frozen_string_literal: true

module Rwm
  module Commands
    class Run
      def initialize(argv)
        @argv = argv
      end

      def run
        task = @argv.shift

        unless task
          $stderr.puts "Usage: rwm run <task>"
          return 1
        end

        workspace = Workspace.find
        graph = DependencyGraph.build(workspace)

        packages = workspace.packages
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

        puts "Running `rake #{task}` across #{runnable.size} package(s)..."
        puts

        runner = TaskRunner.new(graph, packages: runnable)
        runner.run_task(task)

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
    end
  end
end
