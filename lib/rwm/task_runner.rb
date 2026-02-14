# frozen_string_literal: true

require "open3"

module Rwm
  class TaskRunner
    Result = Struct.new(:package_name, :task, :success, :output, keyword_init: true)

    attr_reader :results

    def initialize(graph, packages: nil)
      @graph = graph
      @packages = packages || graph.packages.values
      @results = []
      @mutex = Mutex.new
    end

    # Run a shell command in each package, parallel by execution level.
    # The command_proc receives a Package and returns [command, args] array.
    def run_command(&command_proc)
      levels = compute_levels
      failed = false

      levels.each do |level_packages|
        if failed
          level_packages.each do |pkg|
            record_result(pkg.name, "skipped", false, "Skipped due to earlier failure")
          end
          next
        end

        level_results = run_level(level_packages, &command_proc)
        failed = level_results.any? { |r| !r.success }
      end

      @results
    end

    # Run a rake task in each package
    def run_task(task)
      run_command do |pkg|
        ["bundle", "exec", "rake", task]
      end
    end

    def success?
      @results.all?(&:success)
    end

    def failed_results
      @results.select { |r| !r.success }
    end

    private

    def compute_levels
      # Build execution levels from the graph, but only include packages we're running
      package_names = @packages.map(&:name).to_set
      all_levels = @graph.execution_levels

      all_levels.filter_map do |level_names|
        pkgs = level_names.filter_map do |name|
          @graph.packages[name] if package_names.include?(name)
        end
        pkgs.empty? ? nil : pkgs
      end
    end

    def run_level(packages, &command_proc)
      if packages.size == 1
        # No need to spawn a thread for a single package
        result = run_single(packages.first, &command_proc)
        @mutex.synchronize { @results << result }
        return [result]
      end

      threads = packages.map do |pkg|
        Thread.new do
          result = run_single(pkg, &command_proc)
          @mutex.synchronize { @results << result }
          result
        end
      end

      threads.map(&:value)
    end

    def run_single(pkg, &command_proc)
      cmd = command_proc.call(pkg)
      prefix = "[#{pkg.name}]"

      stdout, stderr, status = Open3.capture3(*cmd, chdir: pkg.path)
      output = format_output(prefix, stdout, stderr)

      print_output(output)

      Result.new(
        package_name: pkg.name,
        task: cmd.join(" "),
        success: status.success?,
        output: output
      )
    end

    def format_output(prefix, stdout, stderr)
      lines = []
      stdout.each_line { |line| lines << "#{prefix} #{line}" }
      stderr.each_line { |line| lines << "#{prefix} #{line}" }
      lines.join
    end

    def print_output(output)
      @mutex.synchronize do
        $stdout.print(output) unless output.empty?
      end
    end

    def record_result(package_name, task, success, output)
      @mutex.synchronize do
        @results << Result.new(
          package_name: package_name,
          task: task,
          success: success,
          output: output
        )
      end
    end
  end
end
