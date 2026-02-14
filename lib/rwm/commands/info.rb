# frozen_string_literal: true

module Rwm
  module Commands
    class Info
      def initialize(argv)
        @argv = argv
      end

      def run
        name = @argv.shift

        unless name
          $stderr.puts "Usage: rwm info <package_name>"
          return 1
        end

        workspace = Workspace.find
        pkg = workspace.find_package(name)
        graph = DependencyGraph.build(workspace)

        deps = graph.dependencies(name)
        dependents = graph.direct_dependents(name)
        transitive = graph.transitive_dependents(name)

        puts "Package:      #{pkg.name}"
        puts "Type:         #{pkg.type}"
        puts "Path:         #{pkg.relative_path(workspace.root)}"
        puts "Has Rakefile: #{pkg.has_rakefile? ? "yes" : "no"}"
        puts "Dependencies: #{deps.empty? ? "(none)" : deps.sort.join(", ")}"
        puts "Dependents:   #{dependents.empty? ? "(none)" : dependents.sort.join(", ")}"

        if transitive.size > dependents.size
          puts "Transitive:   #{transitive.sort.join(", ")}"
        end

        0
      end
    end
  end
end
