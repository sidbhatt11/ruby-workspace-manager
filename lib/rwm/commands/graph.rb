# frozen_string_literal: true

require "optparse"

module Rwm
  module Commands
    class Graph
      def initialize(argv)
        @argv = argv
        @format = nil
        parse_options
      end

      def run
        workspace = Workspace.find
        graph = DependencyGraph.build(workspace)
        graph.save(workspace.graph_path, workspace.root)

        puts "  Graph saved to .rwm/graph.json (#{graph.packages.size} packages, #{graph.edges.values.flatten.size} edges)"

        case @format
        when :dot
          puts graph.to_dot(workspace.root)
        when :mermaid
          puts graph.to_mermaid(workspace.root)
        end

        0
      end

      private

      def parse_options
        OptionParser.new do |opts|
          opts.on("--dot", "Output graph in Graphviz DOT format") do
            @format = :dot
          end

          opts.on("--mermaid", "Output graph in Mermaid format") do
            @format = :mermaid
          end
        end.parse!(@argv)
      end
    end
  end
end
