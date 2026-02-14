# frozen_string_literal: true

require "fileutils"

module Rwm
  module Commands
    class Init
      GEMFILE_TEMPLATE = <<~GEMFILE
        # frozen_string_literal: true

        source "https://rubygems.org"

        gem "rwm"
        gem "overcommit"
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
      end

      def run
        root = Dir.pwd

        create_directories(root)
        create_gemfile(root)
        create_rakefile(root)

        puts "Workspace initialized. Running bootstrap..."
        puts

        # Call bootstrap as the last step
        require "rwm/commands/bootstrap"
        Commands::Bootstrap.new([]).run
      end

      private

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
    end
  end
end
