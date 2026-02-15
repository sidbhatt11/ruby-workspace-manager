# frozen_string_literal: true

# Bundler DSL extension for rwm workspaces.
#
# Usage in a package Gemfile:
#
#   require "rwm/gemfile"
#
#   source "https://rubygems.org"
#   gemspec
#
#   rwm_lib "auth"

require "bundler"
require "open3"
require "set"

module Rwm
  @resolved_libs = Set.new

  def self.resolved_libs
    @resolved_libs
  end

  module GemfileDsl
    def rwm_workspace_root
      @rwm_workspace_root ||= begin
        out, _, status = Open3.capture3("git", "rev-parse", "--show-toplevel")
        root = status.success? ? out.strip : ""
        raise "rwm: not inside a git repository" if root.empty?
        root
      end
    end

    def rwm_lib(name, **opts)
      name = name.to_s
      @rwm_resolved ||= Set.new
      return if @rwm_resolved.include?(name)

      @rwm_resolved.add(name)
      Rwm.resolved_libs.add(name)

      path = File.join(rwm_workspace_root, "libs", name)
      gem(name, **opts, path: path)

      # Resolve transitive workspace deps from the target lib's Gemfile
      target_gemfile = File.join(path, "Gemfile")
      return unless File.exist?(target_gemfile)

      scan_transitive_deps(target_gemfile).each { |dep_name| rwm_lib(dep_name) }
    end

    private

    def scan_transitive_deps(gemfile_path)
      sandbox = Bundler::Dsl.new
      sandbox.eval_gemfile(gemfile_path)

      libs_prefix = File.join(rwm_workspace_root, "libs") + "/"
      gemfile_dir = File.dirname(gemfile_path)

      sandbox.dependencies.each_with_object([]) do |dep, result|
        source = dep.source
        next unless source.is_a?(Bundler::Source::Path)

        dep_path = File.expand_path(source.path.to_s, gemfile_dir)
        next unless dep_path.start_with?(libs_prefix)

        result << File.basename(dep_path)
      end
    end

  end
end

Bundler::Dsl.prepend(Rwm::GemfileDsl)
