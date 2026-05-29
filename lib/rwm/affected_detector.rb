# frozen_string_literal: true

require "open3"

module Rwm
  class AffectedDetector
    IGNORED_ROOT_PATTERNS = [
      "*.md",
      "LICENSE*",
      "CHANGELOG*",
      ".github/**",
      ".vscode/**",
      ".idea/**",
      "docs/**",
      ".rwm/**",
    ].freeze

    IGNORE_FILE = "affected_ignore"

    attr_reader :workspace, :graph, :base_branch

    def initialize(workspace, graph, committed_only: false, base_branch: nil)
      @workspace = workspace
      @graph = graph
      @committed_only = committed_only
      @base_branch = base_branch || detect_base_branch
      # Validate the *resolved* base, auto-detected or explicit. An unreachable base
      # must fail loudly rather than silently report "nothing affected" (false-green CI).
      validate_base_branch!
    end

    # Returns packages directly changed + their transitive dependents
    def affected_packages
      changed_files = detect_changed_files
      directly_changed = map_files_to_packages(changed_files)

      # If root-level files changed (outside any package), all packages are affected
      root_files = changed_files.reject { |f| file_in_any_package?(f) }
      significant_root_files = root_files.reject { |f| ignored_root_file?(f) }

      unless significant_root_files.empty?
        Rwm.debug("affected: significant root files changed: #{significant_root_files.join(', ')}")
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

    def validate_base_branch!
      _, _, status = Open3.capture3("git", "-C", workspace.root, "rev-parse", "--verify", "#{@base_branch}^{commit}")
      return if status.success?

      raise Rwm::InvalidBaseRefError, @base_branch
    end

    def detect_base_branch
      # Try to read the remote's default branch
      ref, _, status = Open3.capture3("git", "-C", workspace.root, "symbolic-ref", "refs/remotes/origin/HEAD")
      if status.success?
        ref = ref.chomp
        unless ref.empty?
          # refs/remotes/origin/main → main
          return ref.sub(%r{^refs/remotes/origin/}, "")
        end
      end

      # Fall back: check if main or master exists
      out, _, status = Open3.capture3("git", "-C", workspace.root, "branch", "--list", "main", "master")
      if status.success?
        branches = out.lines.map(&:strip)
        return "main" if branches.include?("main")
        return "master" if branches.include?("master")
      end

      # Last resort
      "main"
    end

    def detect_changed_files
      files = Set.new

      # 1. Committed changes: base branch vs HEAD. A failure here means we cannot
      # compare against the base (e.g. a shallow clone whose merge-base is below the
      # fetched boundary). That must be loud — a silent empty result false-greens CI.
      Rwm.debug("affected: git diff --name-only #{base_branch}...HEAD")
      committed, committed_err, status = Open3.capture3("git", "-C", workspace.root, "diff", "--name-only", "#{base_branch}...HEAD")
      unless status.success?
        raise Rwm::InvalidBaseRefError.new(
          base_branch,
          reason: "Could not compute changes against base '#{base_branch}': " \
                  "git diff #{base_branch}...HEAD failed (#{committed_err.strip}). " \
                  "If this is a shallow clone, fetch more history " \
                  "(e.g. `git fetch origin #{base_branch} --unshallow`) or pass a valid --base."
        )
      end
      committed.lines.each { |l| files << l.chomp }

      unless @committed_only
        # 2. Staged changes (not yet committed)
        Rwm.debug("affected: git diff --name-only --cached")
        staged, _, status = Open3.capture3("git", "-C", workspace.root, "diff", "--name-only", "--cached")
        staged.lines.each { |l| files << l.chomp } if status.success?

        # 3. Unstaged working directory changes
        Rwm.debug("affected: git diff --name-only")
        unstaged, _, status = Open3.capture3("git", "-C", workspace.root, "diff", "--name-only")
        unstaged.lines.each { |l| files << l.chomp } if status.success?
      end

      result = files.reject(&:empty?).to_a
      Rwm.debug("affected: #{result.size} changed file(s) detected")
      result
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

    def ignored_root_file?(file)
      ignore_patterns.any? do |pattern|
        File.fnmatch(pattern, file, File::FNM_DOTMATCH)
      end
    end

    def ignore_patterns
      patterns = IGNORED_ROOT_PATTERNS.dup
      ignore_file = File.join(workspace.root, ".rwm", IGNORE_FILE)
      if File.exist?(ignore_file)
        File.readlines(ignore_file).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          patterns << line
        end
      end
      patterns
    end
  end
end
