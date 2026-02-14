# frozen_string_literal: true

require "digest"
require "fileutils"

module Rwm
  class TaskCache
    def initialize(workspace, graph)
      @workspace = workspace
      @graph = graph
      @cache_dir = File.join(workspace.root, ".rwm", "cache")
      @content_hashes = {}
    end

    # Returns true if the (package, task) pair is cached and inputs haven't changed
    def cached?(package, task)
      stored = read_stored_hash(package, task)
      return false unless stored

      stored == content_hash(package)
    end

    # Store the current content hash after a successful task run
    def store(package, task)
      FileUtils.mkdir_p(@cache_dir)
      path = cache_file(package, task)
      File.write(path, content_hash(package))
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
