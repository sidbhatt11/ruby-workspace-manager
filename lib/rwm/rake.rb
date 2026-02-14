# frozen_string_literal: true

# Rake DSL extension for rwm workspaces.
#
# Usage in a package Rakefile:
#
#   require "rwm/rake"
#
#   cacheable_task :spec do
#     sh "bundle exec rspec"
#   end
#
#   cacheable_task :build, output: "pkg/*.gem" do
#     sh "gem build *.gemspec"
#   end

require "rake"
require "json"

module Rwm
  module RakeCache
    @declarations = {}

    class << self
      attr_reader :declarations

      def register(task_name, output:)
        @declarations[task_name.to_s] = { "output" => output }
        ensure_cache_config_task
      end

      def reset!
        @declarations = {}
      end

      def ensure_cache_config_task
        return if Rake::Task.task_defined?("rwm:cache_config")

        Rake::Task.define_task("rwm:cache_config") do
          puts JSON.generate(Rwm::RakeCache.declarations)
        end
      end
    end
  end
end

# Top-level DSL method available in Rakefiles
def cacheable_task(name, output: nil, &block)
  Rwm::RakeCache.register(name, output: output)
  Rake::Task.define_task(name, &block)
end
