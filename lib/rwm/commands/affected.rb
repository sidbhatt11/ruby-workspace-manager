# frozen_string_literal: true

require "optparse"

module Rwm
  module Commands
    class Affected
      def initialize(argv)
        @argv = argv
        @committed_only = false
        @base_branch = nil
        parse_options
      end

      def run
        workspace = Workspace.find
        graph = DependencyGraph.load(workspace)
        detector = AffectedDetector.new(workspace, graph, committed_only: @committed_only, base_branch: @base_branch)

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
          opts.on("--base REF", "Compare against REF instead of auto-detected base branch") do |ref|
            @base_branch = ref
          end
          opts.on("--committed", "Only consider committed changes (ignore staged/unstaged)") do
            @committed_only = true
          end
        end

        parser.order!(@argv)
      end
    end
  end
end
