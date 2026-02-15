# frozen_string_literal: true

# Rails integration for RWM workspaces.
#
# Usage in config/application.rb:
#
#   require_relative "boot"
#   require "rwm/rails"
#   Rwm.require_libs
#   require "rails"

require "rwm/gemfile"

module Rwm
  def self.require_libs
    resolved_libs.each { |name| require name }
  end
end
