# frozen_string_literal: true

module Rwm
  module Commands
    class Cache
      def initialize(argv)
        @argv = argv
      end

      def run
        subcommand = @argv.shift

        case subcommand
        when "clean"
          clean
        when nil
          $stderr.puts "Usage: rwm cache clean [<package>]"
          1
        else
          $stderr.puts "Unknown cache subcommand: #{subcommand}"
          $stderr.puts "Usage: rwm cache clean [<package>]"
          1
        end
      end

      private

      def clean
        workspace = Workspace.find
        package_name = @argv.shift

        if package_name
          pkg = workspace.find_package(package_name)
          unless pkg
            $stderr.puts "Unknown package: #{package_name}"
            return 1
          end
          TaskCache.clean(workspace, package_name: package_name)
          puts "Cleared cache for #{package_name}."
        else
          TaskCache.clean(workspace)
          puts "Cleared all cached task results."
        end

        0
      end
    end
  end
end
