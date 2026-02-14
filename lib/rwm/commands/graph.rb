# frozen_string_literal: true

module Rwm
  module Commands
    class Graph
      def initialize(argv)
        @argv = argv
      end

      def run
        workspace = Workspace.find
        graph = DependencyGraph.build(workspace)
        graph.save(workspace.graph_path, workspace.root)

        puts "  Graph saved to .rwm/graph.json (#{graph.packages.size} packages, #{graph.edges.values.flatten.size} edges)"
        0
      end
    end
  end
end
