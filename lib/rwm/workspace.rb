# frozen_string_literal: true

module Rwm
  class Workspace
    RWM_DIR = ".rwm"
    PACKAGE_DIRS = %w[libs apps].freeze
    GRAPH_FILE = "graph.json"

    attr_reader :root

    def initialize(root)
      @root = root
    end

    # Find the workspace root via git
    def self.find(start_dir = Dir.pwd)
      dir = File.expand_path(start_dir)
      git_root = `git -C #{dir} rev-parse --show-toplevel 2>/dev/null`.chomp

      raise WorkspaceNotFoundError if git_root.empty?

      new(git_root)
    end

    def rwm_dir
      File.join(root, RWM_DIR)
    end

    def graph_path
      File.join(rwm_dir, GRAPH_FILE)
    end

    def libs_dir
      File.join(root, "libs")
    end

    def apps_dir
      File.join(root, "apps")
    end

    # Discover all packages by scanning libs/ and apps/ for directories with a Gemfile
    def packages
      @packages ||= discover_packages
    end

    def find_package(name)
      packages.find { |p| p.name == name } || raise(PackageNotFoundError, name)
    end

    private

    def discover_packages
      pkgs = []

      PACKAGE_DIRS.each do |dir_name|
        base = File.join(root, dir_name)
        next unless File.directory?(base)

        type = dir_name == "libs" ? :lib : :app

        Dir.children(base).sort.each do |name|
          pkg_path = File.join(base, name)
          next unless File.directory?(pkg_path)
          next unless File.exist?(File.join(pkg_path, "Gemfile"))

          pkgs << Package.new(name: name, path: pkg_path, type: type)
        end
      end

      pkgs
    end
  end
end
