# frozen_string_literal: true

module Rwm
  class AffectedDetector
    attr_reader :workspace, :graph, :base_branch

    def initialize(workspace, graph, committed_only: false)
      @workspace = workspace
      @graph = graph
      @committed_only = committed_only
      @base_branch = detect_base_branch
    end

    # Returns packages directly changed + their transitive dependents
    def affected_packages
      changed_files = detect_changed_files
      directly_changed = map_files_to_packages(changed_files)

      # If root-level files changed (outside any package), all packages are affected
      root_files = changed_files.reject { |f| file_in_any_package?(f) }
      unless root_files.empty?
        return workspace.packages
      end

      # Collect transitive dependents of directly changed packages
      all_affected = Set.new(directly_changed.map(&:name))
      directly_changed.each do |pkg|
        graph.transitive_dependents(pkg.name).each { |name| all_affected << name }
      end

      workspace.packages.select { |pkg| all_affected.include?(pkg.name) }
    end

    # Just the directly changed packages (no dependents)
    def directly_changed_packages
      changed_files = detect_changed_files
      map_files_to_packages(changed_files)
    end

    private

    def detect_base_branch
      # Try to read the remote's default branch
      ref = `git -C #{workspace.root} symbolic-ref refs/remotes/origin/HEAD 2>/dev/null`.chomp
      unless ref.empty?
        # refs/remotes/origin/main → main
        return ref.sub(%r{^refs/remotes/origin/}, "")
      end

      # Fall back: check if main or master exists
      branches = `git -C #{workspace.root} branch --list main master 2>/dev/null`.lines.map(&:strip)
      return "main" if branches.include?("main")
      return "master" if branches.include?("master")

      # Last resort
      "main"
    end

    def detect_changed_files
      files = Set.new

      # 1. Committed changes: base branch vs HEAD
      committed = `git -C #{workspace.root} diff --name-only #{base_branch}...HEAD 2>/dev/null`.chomp
      committed.lines.each { |l| files << l.chomp }

      unless @committed_only
        # 2. Staged changes (not yet committed)
        staged = `git -C #{workspace.root} diff --name-only --cached 2>/dev/null`.chomp
        staged.lines.each { |l| files << l.chomp }

        # 3. Unstaged working directory changes
        unstaged = `git -C #{workspace.root} diff --name-only 2>/dev/null`.chomp
        unstaged.lines.each { |l| files << l.chomp }
      end

      files.reject(&:empty?).to_a
    end

    def map_files_to_packages(files)
      packages = workspace.packages
      matched = Set.new

      files.each do |file|
        packages.each do |pkg|
          rel_path = pkg.relative_path(workspace.root)
          if file.start_with?("#{rel_path}/")
            matched << pkg
          end
        end
      end

      matched.to_a
    end

    def file_in_any_package?(file)
      workspace.packages.any? do |pkg|
        rel_path = pkg.relative_path(workspace.root)
        file.start_with?("#{rel_path}/")
      end
    end
  end
end
