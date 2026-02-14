# frozen_string_literal: true

require "rwm"
require "tmpdir"
require "fileutils"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random
end

# Helper to create a temporary monorepo fixture
module FixtureHelper
  def create_fixture_workspace(dir, packages: {})
    FileUtils.mkdir_p(File.join(dir, ".rwm"))
    FileUtils.mkdir_p(File.join(dir, "libs"))
    FileUtils.mkdir_p(File.join(dir, "apps"))

    packages.each do |name, opts|
      type = opts[:type] || :lib
      deps = opts[:deps] || []
      parent = type == :lib ? "libs" : "apps"
      pkg_dir = File.join(dir, parent, name.to_s)

      FileUtils.mkdir_p(File.join(pkg_dir, "lib"))

      # Build Gemfile with path dependencies
      gemfile_lines = [
        '# frozen_string_literal: true',
        '',
        'source "https://rubygems.org"',
        '',
        'gemspec',
        ''
      ]

      deps.each do |dep|
        dep_info = packages[dep]
        dep_type = dep_info ? (dep_info[:type] || :lib) : :lib
        dep_parent = dep_type == :lib ? "libs" : "apps"
        rel_path = "../../#{dep_parent}/#{dep}"
        gemfile_lines << "gem \"#{dep}\", path: \"#{rel_path}\""
      end

      File.write(File.join(pkg_dir, "Gemfile"), gemfile_lines.join("\n") + "\n")

      # Minimal gemspec
      File.write(File.join(pkg_dir, "#{name}.gemspec"), <<~GEMSPEC)
        Gem::Specification.new do |spec|
          spec.name = "#{name}"
          spec.version = "0.1.0"
          spec.authors = ["Test"]
          spec.summary = "Test gem"
          spec.files = Dir.glob("lib/**/*")
          spec.require_paths = ["lib"]
        end
      GEMSPEC

      # Rakefile
      if opts[:rakefile] != false
        rakefile_content = opts[:rakefile_content] || <<~RAKEFILE
          task :spec do; end
          task :bootstrap do; end
          task default: :spec
        RAKEFILE
        File.write(File.join(pkg_dir, "Rakefile"), rakefile_content)
      end

      # lib entry
      mod_name = name.to_s.split("_").map(&:capitalize).join
      File.write(File.join(pkg_dir, "lib", "#{name}.rb"), <<~RUBY)
        module #{mod_name}; end
      RUBY
    end

    dir
  end
end

RSpec.configure do |config|
  config.include FixtureHelper
end
