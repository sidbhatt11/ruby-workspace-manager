# frozen_string_literal: true

module Rwm
  module Commands
    class Check
      def initialize(argv)
        @argv = argv
      end

      def run
        workspace = Workspace.find
        graph = DependencyGraph.build(workspace)
        checker = ConventionChecker.new(graph)
        violations = checker.check

        if violations.empty?
          puts "  All conventions passed."
          0
        else
          $stderr.puts "Convention violations found:"
          violations.each { |v| $stderr.puts "  - #{v}" }
          1
        end
      end
    end
  end
end
