# frozen_string_literal: true

require "pathname"
require "open3"

module Rwm
  class Package
    attr_reader :name, :path, :type

    def initialize(name:, path:, type:)
      @name = name
      @path = File.expand_path(path)
      @type = type.to_sym
    end

    def lib?
      type == :lib
    end

    def app?
      type == :app
    end

    def has_rakefile?
      File.exist?(File.join(path, "Rakefile"))
    end

    def has_rake_task?(task)
      return false unless has_rakefile?

      output, _, status = Open3.capture3("bundle", "exec", "rake", "-P", chdir: path)
      return false unless status.success?

      output.lines.any? { |line| line.strip == "rake #{task}" }
    end

    def gemfile_path
      File.join(path, "Gemfile")
    end

    def gemspec_path
      Dir.glob(File.join(path, "*.gemspec")).first
    end

    def relative_path(workspace_root)
      Pathname.new(path).relative_path_from(Pathname.new(workspace_root)).to_s
    end

    def to_s
      "#{name} (#{type})"
    end

    def ==(other)
      other.is_a?(Package) && name == other.name && path == other.path
    end
    alias eql? ==

    def hash
      [name, path].hash
    end
  end
end
