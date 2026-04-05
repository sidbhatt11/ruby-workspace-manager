# frozen_string_literal: true

module Rwm
  class CLI
    COMMANDS = {
      "init"      => "Commands::Init",
      "bootstrap" => "Commands::Bootstrap",
      "new"       => "Commands::New",
      "info"      => "Commands::Info",
      "graph"     => "Commands::Graph",
      "check"     => "Commands::Check",
      "list"      => "Commands::List",
      "run"       => "Commands::Run",
      "affected"  => "Commands::Affected",
      "cache"     => "Commands::Cache"
    }.freeze

    def self.run(argv)
      new(argv).run
    end

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      parse_global_flags

      command_name = @argv.shift

      if command_name.nil? || %w[-h --help help].include?(command_name)
        print_help
        return 0
      end

      if %w[-v --version version].include?(command_name)
        puts "rwm #{Rwm::VERSION}"
        return 0
      end

      check_required_tools

      # Unknown commands are treated as task names: `rwm test` → `rwm run test`
      unless COMMANDS.key?(command_name)
        @argv.unshift(command_name)
        command_name = "run"
      end

      # Autoload the command
      require "rwm/commands/#{command_name}"
      const_name = COMMANDS[command_name]
      command_class = const_name.split("::").reduce(Rwm) { |mod, name| mod.const_get(name) }
      command_class.new(@argv).run
    rescue Interrupt
      $stderr.puts "\nInterrupted."
      130
    rescue Rwm::Error => e
      $stderr.puts "Error: #{e.message}"
      1
    rescue StandardError => e
      $stderr.puts "Error: #{e.message}"
      Rwm.debug("#{e.class}: #{e.message}\n#{e.backtrace&.join("\n")}")
      1
    end

    private

    def parse_global_flags
      Rwm.verbose = true if ENV["RWM_DEBUG"] == "1"
      if @argv.delete("--verbose")
        Rwm.verbose = true
      end
    end

    def check_required_tools
      %w[git bundle].each do |tool|
        unless system("which", tool, out: File::NULL, err: File::NULL)
          raise Rwm::Error, "#{tool} is not installed or not in PATH."
        end
      end
    end

    def print_help
      puts <<~HELP
        rwm #{Rwm::VERSION} — Ruby Workspace Manager

        Usage: rwm <command> [options]

        Commands:
          init [--vscode]   Initialize a new rwm workspace
          bootstrap [pkg...] Install deps and run bootstrap (all if none given)
          new <type> <name> Scaffold a new app or lib
          info <name>       Show details about a package
          graph             Build and save the dependency graph
            --dot           Output in Graphviz DOT format
            --mermaid       Output in Mermaid format
          check             Validate dependency graph and conventions
          run <task> [pkg...]  Run a rake task across packages (all if none given)
          affected          Show packages affected by current changes
            --base REF      Compare against REF instead of auto-detected base
            --committed     Only consider committed changes
          list              List all packages in the workspace
          cache clean [pkg] Clear cached task results
          help              Show this help
          version           Show version

        Any unrecognized command is treated as a task name:
          rwm test              → rwm run test
          rwm test auth billing → rwm run test auth billing

        Run options (for `rwm run` and task shortcuts):
          --affected        Only run on affected packages
          --committed       Only consider committed changes (with --affected)
          --base REF        Compare against REF instead of auto-detected base
          --dry-run         Show what would run without executing
          --no-cache        Bypass task-level caching
          --buffered        Buffer output per-package
          --concurrency N   Max parallel workers (default: CPU count)

        Global options:
          -h, --help        Show this help
          -v, --version     Show version
          --verbose         Enable debug logging (or set RWM_DEBUG=1)
      HELP
    end
  end
end
