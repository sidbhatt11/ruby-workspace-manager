# frozen_string_literal: true

require "tsort"
require "json"
require "fileutils"

module Rwm
  class DependencyGraph
    include TSort

    attr_reader :packages, :edges

    def initialize
      @packages = {}   # name => Package
      @edges = {}      # name => [dep_name, ...]
      @dependents = {} # name => [dependent_name, ...]
    end

    def add_package(package)
      @packages[package.name] = package
      @edges[package.name] ||= []
      @dependents[package.name] ||= []
    end

    def add_edge(from_name, to_name)
      @edges[from_name] ||= []
      @edges[from_name] << to_name unless @edges[from_name].include?(to_name)
      @dependents[to_name] ||= []
      @dependents[to_name] << from_name unless @dependents[to_name].include?(from_name)
    end

    # Dependencies of a package (what it depends on)
    def dependencies(name)
      @edges[name] || []
    end

    # Direct dependents of a package (what depends on it)
    def direct_dependents(name)
      @dependents[name] || []
    end

    # Walk the graph to find all transitive dependents
    def transitive_dependents(name)
      visited = Set.new
      queue = [name]

      until queue.empty?
        current = queue.shift
        direct_dependents(current).each do |dep|
          next if visited.include?(dep)

          visited << dep
          queue << dep
        end
      end

      visited.to_a
    end

    # Topological sort (dependencies before dependents)
    def topological_order
      tsort
    rescue TSort::Cyclic => e
      raise CycleError, [e.message]
    end

    # Group packages into execution levels — packages at the same level
    # have no interdependencies and can run in parallel
    def execution_levels
      return [] if @packages.empty?

      remaining = @packages.keys.dup
      levels = []

      until remaining.empty?
        # Find packages whose deps are all already placed in earlier levels
        placed = levels.flatten
        level = remaining.select do |name|
          dependencies(name).all? { |dep| placed.include?(dep) }
        end

        raise CycleError, ["Unable to resolve execution levels — possible cycle"] if level.empty?

        levels << level.sort
        remaining -= level
      end

      levels
    end

    # Load graph from cached .rwm/graph.json, falling back to build.
    # Auto-rebuilds when any package Gemfile is newer than the cache.
    def self.load(workspace)
      path = workspace.graph_path
      unless File.exist?(path)
        return build_and_save(workspace)
      end

      if stale?(path, workspace.packages)
        return build_and_save(workspace)
      end

      data = JSON.parse(File.read(path))
      graph = new

      workspace.packages.each { |pkg| graph.add_package(pkg) }

      data["edges"]&.each do |name, deps|
        deps.each { |dep| graph.add_edge(name, dep) }
      end

      graph
    end

    def self.build_and_save(workspace)
      graph = build(workspace)
      graph.save(workspace.graph_path, workspace.root)
      graph
    end

    def self.stale?(graph_path, packages)
      graph_mtime = File.mtime(graph_path)
      packages.any? { |pkg| File.mtime(pkg.gemfile_path) > graph_mtime }
    end

    private_class_method :stale?, :build_and_save

    # Build graph from a workspace by parsing all Gemfiles
    def self.build(workspace)
      graph = new

      workspace.packages.each { |pkg| graph.add_package(pkg) }

      workspace.packages.each do |pkg|
        deps = GemfileParser.parse(pkg.gemfile_path, workspace.packages)
        deps.each { |dep| graph.add_edge(pkg.name, dep.name) }
      end

      graph
    end

    # Serialize to JSON for .rwm/graph.json
    def to_json_data
      {
        "version" => 1,
        "generated_at" => Time.now.iso8601,
        "packages" => @packages.transform_values do |pkg|
          { "name" => pkg.name, "type" => pkg.type.to_s, "path" => pkg.relative_path(@workspace_root || "") }
        end,
        "edges" => @edges.transform_values(&:sort)
      }
    end

    def save(path, workspace_root)
      @workspace_root = workspace_root
      dir = File.dirname(path)
      FileUtils.mkdir_p(dir)
      File.write(path, JSON.pretty_generate(to_json_data) + "\n")
    end

    def self.load_from_file(path)
      data = JSON.parse(File.read(path))
      graph = new

      # We can't reconstruct full Package objects from JSON alone,
      # but we can load the structure for validation
      data["edges"]&.each do |name, deps|
        graph.instance_variable_get(:@edges)[name] = deps
        deps.each do |dep|
          graph.instance_variable_get(:@dependents)[dep] ||= []
          graph.instance_variable_get(:@dependents)[dep] << name
        end
      end

      graph
    end

    def to_dot(workspace_root)
      lines = []
      lines << "digraph rwm {"
      lines << "  rankdir=LR;"
      lines << "  node [shape=box];"

      @packages.each_value do |pkg|
        lines << "  \"#{pkg.name}\" [label=\"#{pkg.name} (#{pkg.type})\"];"
      end

      @edges.each do |from, deps|
        deps.each do |to|
          lines << "  \"#{from}\" -> \"#{to}\";"
        end
      end

      lines << "}"
      lines.join("\n") + "\n"
    end

    def to_mermaid(workspace_root)
      lines = []
      lines << "graph LR"

      @packages.each_value do |pkg|
        lines << "  #{pkg.name}[\"#{pkg.name} (#{pkg.type})\"]"
      end

      @edges.each do |from, deps|
        deps.each do |to|
          lines << "  #{from} --> #{to}"
        end
      end

      lines.join("\n") + "\n"
    end

    private

    # TSort interface
    def tsort_each_node(&block)
      @packages.each_key(&block)
    end

    def tsort_each_child(node, &block)
      (@edges[node] || []).each(&block)
    end
  end
end
