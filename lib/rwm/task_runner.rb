# frozen_string_literal: true

require "open3"
require "etc"

module Rwm
  class TaskRunner
    Result = Struct.new(:package_name, :task, :success, :output, keyword_init: true)

    attr_reader :results

    def initialize(graph, packages: nil, buffered: false, concurrency: Etc.nprocessors)
      @graph = graph
      @packages = packages || graph.packages.values
      @buffered = buffered
      @concurrency = concurrency
      @results = []
      @mutex = Mutex.new
    end

    # Run a shell command in each package using DAG scheduling.
    # Starts each package as soon as its dependencies complete.
    # The command_proc receives a Package and returns [command, args] array.
    def run_command(&command_proc)
      package_names = @packages.map(&:name).to_set

      pending = @packages.dup
      completed = Set.new
      skipped = Set.new
      running = {}

      mutex = Mutex.new
      condition = ConditionVariable.new

      until pending.empty? && running.empty?
        mutex.synchronize do
          ready = pending.select { |pkg| ready?(pkg, package_names, completed) }

          ready.each do |pkg|
            break if running.size >= @concurrency

            pending.delete(pkg)
            running[pkg.name] = Thread.new do
              result = run_single(pkg, &command_proc)
              mutex.synchronize do
                @results << result
                running.delete(pkg.name)
                if result.success
                  completed << pkg.name
                else
                  skip_names = @graph.transitive_dependents(pkg.name)
                                     .select { |n| package_names.include?(n) }
                  skip_names.each do |name|
                    skip_pkg = pending.find { |p| p.name == name }
                    if skip_pkg
                      pending.delete(skip_pkg)
                      skipped << name
                      @results << Result.new(
                        package_name: name, task: "skipped",
                        success: false, output: "Skipped due to failed dependency: #{pkg.name}"
                      )
                    end
                  end
                end
                condition.broadcast
              end
            end
          end

          if running.any? && ready.empty?
            condition.wait(mutex)
          end
        end
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

    def ready?(pkg, run_set, completed)
      @graph.dependencies(pkg.name).each do |dep|
        next unless run_set.include?(dep)

        return false unless completed.include?(dep)
      end
      true
    end

    def run_single(pkg, &command_proc)
      cmd = command_proc.call(pkg)
      prefix = "[#{pkg.name}]"

      stdout, stderr, status = Open3.capture3(*cmd, chdir: pkg.path)
      output = format_output(prefix, stdout, stderr)

      if @buffered
        print_buffered_output(pkg.name, output, status.success?)
      else
        print_output(output)
      end

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

    def print_buffered_output(name, output, success)
      @mutex.synchronize do
        stream = success ? $stdout : $stderr
        stream.puts "==> [#{name}]"
        stream.print(output) unless output.empty?
        stream.puts
      end
    end
  end
end
