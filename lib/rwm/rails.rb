# frozen_string_literal: true

# Rails integration for RWM workspaces.
#
# For standard Rails apps, Bundler.require handles workspace libs
# automatically — no manual require_libs call is needed.
#
# This file is for non-standard setups or explicit control:
#
#   require "rwm/rails"
#   Rwm.require_libs

require "rwm/gemfile"

module Rwm
  @libs_required = false

  def self.libs_required?
    @libs_required
  end

  def self.require_libs
    return if @libs_required

    resolved_libs.each { |name| require name }
    @libs_required = true
    debug("required #{resolved_libs.size} workspace lib(s): #{resolved_libs.to_a.sort.join(', ')}")
  end
end
