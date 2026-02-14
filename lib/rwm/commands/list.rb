# frozen_string_literal: true

module Rwm
  module Commands
    class List
      def initialize(argv)
        @argv = argv
      end

      def run
        workspace = Workspace.find
        packages = workspace.packages

        if packages.empty?
          puts "No packages found."
          return 0
        end

        graph = DependencyGraph.build(workspace)

        # Calculate column widths
        name_width = [packages.map { |p| p.name.length }.max, 4].max
        type_width = 4
        path_width = [packages.map { |p| p.relative_path(workspace.root).length }.max, 4].max

        # Header
        puts format("%-#{name_width}s  %-#{type_width}s  %-#{path_width}s  %s",
                     "Name", "Type", "Path", "Dependencies")
        puts format("%-#{name_width}s  %-#{type_width}s  %-#{path_width}s  %s",
                     "-" * name_width, "-" * type_width, "-" * path_width, "-" * 12)

        # Rows
        packages.each do |pkg|
          deps = graph.dependencies(pkg.name)
          dep_str = deps.empty? ? "(none)" : deps.sort.join(", ")

          puts format("%-#{name_width}s  %-#{type_width}s  %-#{path_width}s  %s",
                       pkg.name, pkg.type, pkg.relative_path(workspace.root), dep_str)
        end

        0
      end
    end
  end
end
