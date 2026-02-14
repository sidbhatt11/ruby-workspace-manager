# frozen_string_literal: true

require "bundler"

module Rwm
  class GemfileParser
    # Parse a Gemfile and extract path dependencies that match known packages
    def self.parse(gemfile_path, known_packages)
      new(gemfile_path, known_packages).parse
    end

    def initialize(gemfile_path, known_packages)
      @gemfile_path = gemfile_path
      @known_packages = known_packages
      @package_by_path = index_packages_by_path
    end

    def parse
      dsl = Bundler::Dsl.new
      dsl.eval_gemfile(@gemfile_path)
      deps = dsl.dependencies

      gemfile_dir = File.expand_path(File.dirname(@gemfile_path))

      deps.each_with_object([]) do |dep, result|
        source = dep.source
        next unless source.is_a?(Bundler::Source::Path)

        # Resolve the path relative to the Gemfile's directory
        dep_path = File.expand_path(source.path.to_s, gemfile_dir)

        # Skip self-references (gemspec directive points to own directory)
        next if dep_path == gemfile_dir

        matched = @package_by_path[dep_path]
        result << matched if matched
      end
    end

    private

    def index_packages_by_path
      @known_packages.each_with_object({}) do |pkg, index|
        index[pkg.path] = pkg
      end
    end
  end
end
