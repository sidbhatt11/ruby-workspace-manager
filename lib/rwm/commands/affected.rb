# frozen_string_literal: true

module Rwm
  module Commands
    class Affected
      def initialize(argv)
        @argv = argv
      end

      def run
        workspace = Workspace.find
        graph = DependencyGraph.build(workspace)
        detector = AffectedDetector.new(workspace, graph)

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
    end
  end
end
