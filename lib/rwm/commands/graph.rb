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
          puts graph.to_dot
        when :mermaid
          puts graph.to_mermaid
        else
          # Show a brief package listing when no format is requested
          unless graph.packages.empty?
            graph.packages.each_value do |pkg|
              deps = graph.edges[pkg.name] || []
              dep_str = deps.empty? ? "" : " → #{deps.join(", ")}"
              puts "  #{pkg.lib? ? "lib" : "app"}/#{pkg.name}#{dep_str}"
            end
          end
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
