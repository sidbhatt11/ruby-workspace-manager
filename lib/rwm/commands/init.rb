# frozen_string_literal: true

require "fileutils"
require "optparse"

module Rwm
  module Commands
    class Init
      GEMFILE_TEMPLATE = <<~GEMFILE
        # frozen_string_literal: true

        source "https://rubygems.org"

        gem "ruby_workspace_manager"
      GEMFILE

      RAKEFILE_TEMPLATE = <<~RAKEFILE
        # frozen_string_literal: true

        task :bootstrap do
          puts "Add your workspace-level bootstrap steps here."
          puts "This task runs during `rwm bootstrap` — use it for binstubs, shared tooling, etc."
        end
      RAKEFILE

      def initialize(argv)
        @argv = argv
        @vscode = false
        parse_options
      end

      def run
        root = Dir.pwd

        create_directories(root)
        create_gemfile(root)
        create_rakefile(root)
        update_gitignore(root)

        if @vscode
          generate_vscode_workspace(root)
        end

        puts "Workspace initialized. Running bootstrap..."
        puts

        # Call bootstrap as the last step
        require "rwm/commands/bootstrap"
        Commands::Bootstrap.new([]).run
      end

      private

      def parse_options
        OptionParser.new do |opts|
          opts.on("--vscode", "Generate VSCode .code-workspace file") do
            @vscode = true
          end
        end.parse!(@argv)
      end

      def create_directories(root)
        %w[libs apps].each do |dir|
          path = File.join(root, dir)
          unless File.directory?(path)
            FileUtils.mkdir_p(path)
            puts "Created #{dir}/"
          end
        end
      end

      def create_gemfile(root)
        path = File.join(root, "Gemfile")
        return if File.exist?(path)

        File.write(path, GEMFILE_TEMPLATE)
        puts "Created Gemfile"
      end

      def create_rakefile(root)
        path = File.join(root, "Rakefile")
        return if File.exist?(path)

        File.write(path, RAKEFILE_TEMPLATE)
        puts "Created Rakefile"
      end

      def generate_vscode_workspace(root)
        VscodeWorkspace.new(root).generate([])
        puts "Created #{File.basename(root)}.code-workspace"
      end

      def update_gitignore(root)
        path = File.join(root, ".gitignore")
        entry = ".rwm/"

        if File.exist?(path)
          content = File.read(path)
          return if content.lines.any? { |line| line.strip == entry }

          File.open(path, "a") do |f|
            f.puts unless content.end_with?("\n")
            f.puts entry
          end
          puts "Added #{entry} to .gitignore"
        else
          File.write(path, "#{entry}\n")
          puts "Created .gitignore"
        end
      end
    end
  end
end
