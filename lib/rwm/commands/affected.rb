# frozen_string_literal: true

require "optparse"

module Rwm
  module Commands
    class Affected
      def initialize(argv)
        @argv = argv
        @committed_only = false
        parse_options
      end

      def run
        workspace = Workspace.find
        graph = DependencyGraph.load(workspace)
        detector = AffectedDetector.new(workspace, graph, committed_only: @committed_only)

        affected = detector.affected_packages
        directly_changed = detector.directly_changed_packages

        if affected.empty?
          puts "No packages affected."
          return 0
        end

        puts "Base branch: #{detector.base_branch}"
        puts "Affected packages (#{affected.size}):"
        puts

        affected.each do |pkg|
          marker = directly_changed.include?(pkg) ? "(changed)" : "(dependent)"
          puts "  #{pkg.name} #{marker}"
        end

        0
      end

      private

      def parse_options
        parser = OptionParser.new do |opts|
          opts.on("--committed", "Only consider committed changes (ignore staged/unstaged)") do
            @committed_only = true
          end
        end

        parser.order!(@argv)
      end
    end
  end
end
