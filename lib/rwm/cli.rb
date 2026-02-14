# frozen_string_literal: true

require "optparse"

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
      "affected"  => "Commands::Affected"
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
      command_name = @argv.shift

      if command_name.nil? || %w[-h --help help].include?(command_name)
        print_help
        return 0
      end

      if %w[-v --version version].include?(command_name)
        puts "rwm #{Rwm::VERSION}"
        return 0
      end

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
          check             Validate dependency graph and conventions
          run <task>        Run a rake task across all packages (parallel)
          test              Shortcut for `rwm run test`
          affected          Show packages affected by current changes
          list              List all packages in the workspace

        Options:
          -h, --help        Show this help
          -v, --version     Show version
      HELP
    end
  end
end
