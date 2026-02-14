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

module Rwm
  module GemfileDsl
    def rwm_workspace_root
      @rwm_workspace_root ||= `git rev-parse --show-toplevel 2>/dev/null`.strip.tap do |root|
        raise "rwm: not inside a git repository" if root.empty?
      end
    end

    def rwm_lib(name, **opts)
      path = File.join(rwm_workspace_root, "libs", name.to_s)
      gem(name.to_s, **opts, path: path)
    end

  end
end

Bundler::Dsl.prepend(Rwm::GemfileDsl)
