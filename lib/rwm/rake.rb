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
def cacheable_task(*args, **opts, &block)
  output = opts.delete(:output)

  # Remaining keyword opts are Rake dependency syntax (e.g. seed: :environment)
  args << opts unless opts.empty?

  # Resolve the task name using Rake's own parser (dup because resolve_args mutates)
  task_name, = Rake.application.resolve_args(args.dup)

  Rwm::RakeCache.register(task_name, output: output)

  # Clear existing actions so we replace rather than stack (e.g. rspec-rails :spec)
  Rake::Task[task_name].clear_actions if Rake::Task.task_defined?(task_name)

  Rake::Task.define_task(*args, &block)
end
