# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "shellwords"

module Rwm
  class TaskCache
    def initialize(workspace, graph)
      @workspace = workspace
      @graph = graph
      @cache_dir = File.join(workspace.root, ".rwm", "cache")
      @content_hashes = {}
      @cache_declarations = {}
    end

    # Returns true if the task is declared cacheable in the package's Rakefile
    def cacheable?(package, task)
      declarations = cache_declarations(package)
      declarations.key?(task)
    end

    # Returns true if the (package, task) pair is cached and inputs haven't changed.
    # Also verifies declared outputs exist (if any).
    def cached?(package, task)
      stored = read_stored_hash(package, task)
      return false unless stored
      return false unless stored == content_hash(package)

      # If outputs are declared, they must exist
      decl = cache_declarations(package)[task]
      if decl && decl["output"]
        return false unless outputs_exist?(package, decl["output"])
      end

      true
    end

    # Store the current content hash after a successful task run
    def store(package, task)
      FileUtils.mkdir_p(@cache_dir)
      path = cache_file(package, task)
      File.write(path, content_hash(package))
    end

    # Check if declared output files/globs exist in the package directory
    def outputs_exist?(package, output_pattern)
      matches = Dir.glob(File.join(package.path, output_pattern))
      !matches.empty?
    end

    # Compute a content hash for a package: SHA256 of all source files + dependency hashes
    def content_hash(package)
      return @content_hashes[package.name] if @content_hashes.key?(package.name)

      digest = Digest::SHA256.new

      # Hash all source files in the package (sorted for determinism)
      source_files(package).each do |file|
        rel_path = file.delete_prefix("#{package.path}/")
        digest.update(rel_path)
        digest.update(File.read(file))
      end

      # Include dependency content hashes (transitive invalidation)
      @graph.dependencies(package.name).sort.each do |dep_name|
        dep_pkg = @workspace.find_package(dep_name)
        digest.update(content_hash(dep_pkg))
      rescue PackageNotFoundError
        next
      end

      @content_hashes[package.name] = digest.hexdigest
    end

    # Discover cacheable task declarations by running `bundle exec rake rwm:cache_config`
    def cache_declarations(package)
      return @cache_declarations[package.name] if @cache_declarations.key?(package.name)

      output = `cd #{Shellwords.escape(package.path)} && bundle exec rake rwm:cache_config 2>/dev/null`
      @cache_declarations[package.name] = if $?.success? && !output.strip.empty?
                                             JSON.parse(output.strip)
                                           else
                                             {}
                                           end
    rescue JSON::ParserError
      @cache_declarations[package.name] = {}
    end

    private

    def source_files(package)
      Dir.glob(File.join(package.path, "**", "*"))
         .select { |f| File.file?(f) }
         .reject { |f| f.include?("/tmp/") || f.include?("/vendor/") || f.include?("/.bundle/") }
         .sort
    end

    def cache_file(package, task)
      File.join(@cache_dir, "#{package.name}-#{task}")
    end

    def read_stored_hash(package, task)
      path = cache_file(package, task)
      return nil unless File.exist?(path)

      File.read(path).strip
    end
  end
end
