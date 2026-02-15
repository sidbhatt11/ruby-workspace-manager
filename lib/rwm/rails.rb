# frozen_string_literal: true

# Rails integration for RWM workspaces.
#
# Usage in config/application.rb:
#
#   require_relative "boot"
#   require "rwm/rails"
#   Rwm.require_libs
#   require "rails"

require "open3"

module Rwm
  def self.require_libs
    root = workspace_root or return
    libs_dir = File.join(root, "libs")
    return unless File.directory?(libs_dir)

    Dir.children(libs_dir).sort.each do |name|
      next unless File.directory?(File.join(libs_dir, name))
      next unless File.exist?(File.join(libs_dir, name, "Gemfile"))

      require name
    rescue LoadError
      # Lib is not in the current bundle — skip it
    end
  end

  def self.workspace_root
    out, _, status = Open3.capture3("git", "rev-parse", "--show-toplevel")
    status.success? ? out.strip : nil
  end
  private_class_method :workspace_root
end
