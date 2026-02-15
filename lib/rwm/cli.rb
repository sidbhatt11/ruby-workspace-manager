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

    # Shortcuts that expand to `run <task>`
    TASK_SHORTCUTS = %w[test spec build].freeze

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

      # Expand task shortcuts: `rwm test` → `rwm run test`
      if TASK_SHORTCUTS.include?(command_name)
        @argv.unshift(command_name)
        command_name = "run"
      end

      const_name = COMMANDS[command_name]
      unless const_name
        $stderr.puts "Unknown command: #{command_name}"
        $stderr.puts "Run `rwm help` for available commands."
        return 1
      end

      # Autoload the command
      require "rwm/commands/#{command_name}"
      command_class = const_name.split("::").reduce(Rwm) { |mod, name| mod.const_get(name) }
      command_class.new(@argv).run
    rescue Rwm::Error => e
      $stderr.puts "Error: #{e.message}"
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
          init              Initialize a new rwm workspace
          bootstrap         Install deps and run bootstrap tasks in all packages
          new <type> <name> Scaffold a new app or lib
          info <name>       Show details about a package
          graph             Build and save the dependency graph
            --dot           Output in Graphviz DOT format
            --mermaid       Output in Mermaid format
          check             Validate dependency graph and conventions
          run <task> [pkg]  Run a rake task across all (or one) package(s)
          test              Shortcut for `rwm run test`
          affected          Show packages affected by current changes
          list              List all packages in the workspace
          cache clean [pkg] Clear cached task results
          help              Show this help

        Run options:
          --affected        Only run on affected packages
          --committed       Only consider committed changes (with --affected)
          --base REF        Compare against REF instead of auto-detected base
          --dry-run         Show what would run without executing
          --no-cache        Bypass task-level caching
          --buffered        Buffer output per-package
          --concurrency N   Max parallel workers (default: CPU count)

        Options:
          -h, --help        Show this help
          -v, --version     Show version
          --verbose         Enable debug logging (or set RWM_DEBUG=1)
      HELP
    end
  end
end
