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

module Rwm
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
      path = File.join(rwm_workspace_root, "libs", name.to_s)
      gem(name.to_s, **opts, path: path)
    end

  end
end

Bundler::Dsl.prepend(Rwm::GemfileDsl)
