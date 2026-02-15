# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"

module Rwm
  class TaskCache
    def self.clean(workspace, package_name: nil)
      cache_dir = File.join(workspace.root, ".rwm", "cache")
      return unless Dir.exist?(cache_dir)

      if package_name
        Dir.glob(File.join(cache_dir, "#{package_name}-*")).each { |f| File.delete(f) }
      else
        Dir.glob(File.join(cache_dir, "*")).each { |f| File.delete(f) }
      end
    end

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
      unless stored
        Rwm.debug("cache miss: #{package.name}:#{task} (no stored hash)")
        return false
      end

      current = content_hash(package)
      unless stored == current
        Rwm.debug("cache miss: #{package.name}:#{task} (hash changed)")
        return false
      end

      # If outputs are declared, they must exist
      decl = cache_declarations(package)[task]
      if decl && decl["output"]
        unless outputs_exist?(package, decl["output"])
          Rwm.debug("cache miss: #{package.name}:#{task} (outputs missing)")
          return false
        end
      end

      Rwm.debug("cache hit: #{package.name}:#{task}")
      true
    end

    # Store the current content hash after a successful task run
    def store(package, task)
      Rwm.debug("cache store: #{package.name}:#{task}")
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

      # Include dependency content hashes (transitive invalidation).
      # If a dependency is missing, let it raise — a stale graph should
      # not silently produce incorrect cache hits.
      @graph.dependencies(package.name).sort.each do |dep_name|
        dep_pkg = @workspace.find_package(dep_name)
        digest.update(content_hash(dep_pkg))
      end

      @content_hashes[package.name] = digest.hexdigest
    end

    # Discover cacheable task declarations by running `bundle exec rake rwm:cache_config`
    def cache_declarations(package)
      return @cache_declarations[package.name] if @cache_declarations.key?(package.name)

      Rwm.debug("cache declarations: discovering for #{package.name}")
      output, _, status = Open3.capture3("bundle", "exec", "rake", "rwm:cache_config", chdir: package.path)
      @cache_declarations[package.name] = if status.success? && !output.strip.empty?
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
         .reject do |f|
           rel = f.delete_prefix("#{package.path}/")
           rel.start_with?("tmp/") || rel.start_with?("vendor/") || rel.start_with?(".bundle/")
         end
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
