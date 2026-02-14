# frozen_string_literal: true

require "fileutils"

module Rwm
  module Commands
    class New
      def initialize(argv)
        @argv = argv
      end

      def run
        type = @argv.shift
        name = @argv.shift

        unless %w[app lib].include?(type)
          $stderr.puts "Usage: rwm new <app|lib> <name>"
          return 1
        end

        unless name && name.match?(/\A[a-z][a-z0-9_]*\z/)
          $stderr.puts "Package name must start with a lowercase letter and contain only lowercase letters, digits, and underscores."
          return 1
        end

        workspace = Workspace.find
        dir = type == "lib" ? "libs" : "apps"
        pkg_path = File.join(workspace.root, dir, name)

        raise PackageExistsError, name if File.directory?(pkg_path)

        scaffold(pkg_path, name, type)
        update_vscode_workspace(workspace)

        puts "Created #{type} '#{name}' at #{dir}/#{name}/"
        puts
        puts "Next steps:"
        puts "  cd #{dir}/#{name}"
        puts "  bundle install"
        puts "  rwm graph    # rebuild the dependency graph"
        0
      end

      private

      def update_vscode_workspace(workspace)
        vscode = VscodeWorkspace.new(workspace.root)
        return unless File.exist?(vscode.file_path)

        # Use a fresh Workspace to pick up the newly scaffolded package
        fresh_workspace = Workspace.find(workspace.root)
        VscodeWorkspace.new(fresh_workspace.root).generate(fresh_workspace.packages)
      end

      def scaffold(pkg_path, name, type)
        FileUtils.mkdir_p(File.join(pkg_path, "lib", name))
        FileUtils.mkdir_p(File.join(pkg_path, "spec"))

        write_gemfile(pkg_path, name)
        write_gemspec(pkg_path, name, type)
        write_rakefile(pkg_path, name)
        write_lib_entry(pkg_path, name)
        write_spec_helper(pkg_path)
      end

      def write_gemfile(pkg_path, name)
        File.write(File.join(pkg_path, "Gemfile"), <<~GEMFILE)
          # frozen_string_literal: true

          source "https://rubygems.org"

          gemspec

          require "rwm/gemfile"
          # rwm_lib "some_dependency"
        GEMFILE
      end

      def write_gemspec(pkg_path, name, type)
        File.write(File.join(pkg_path, "#{name}.gemspec"), <<~GEMSPEC)
          # frozen_string_literal: true

          Gem::Specification.new do |spec|
            spec.name = "#{name}"
            spec.version = "0.1.0"
            spec.authors = ["TODO: Your name"]
            spec.summary = "TODO: Summary of #{name}"

            spec.files = Dir.glob("lib/**/*")
            spec.require_paths = ["lib"]
            spec.required_ruby_version = ">= 3.1.0"

            spec.add_development_dependency "rake"
            spec.add_development_dependency "rspec"
            spec.add_development_dependency "rwm"
          end
        GEMSPEC
      end

      def write_rakefile(pkg_path, name)
        File.write(File.join(pkg_path, "Rakefile"), <<~RAKEFILE)
          # frozen_string_literal: true

          require "rwm/rake"

          cacheable_task :spec do
            sh "bundle exec rspec"
          end

          task :bootstrap do
            puts "Add bootstrap steps for #{name} here."
          end

          task default: :spec
        RAKEFILE
      end

      def write_lib_entry(pkg_path, name)
        File.write(File.join(pkg_path, "lib", "#{name}.rb"), <<~RUBY)
          # frozen_string_literal: true

          module #{camelize(name)}
          end
        RUBY
      end

      def write_spec_helper(pkg_path)
        File.write(File.join(pkg_path, "spec", "spec_helper.rb"), <<~RUBY)
          # frozen_string_literal: true

          RSpec.configure do |config|
            config.expect_with :rspec do |expectations|
              expectations.include_chain_clauses_in_custom_matcher_descriptions = true
            end
          end
        RUBY
      end

      def camelize(name)
        name.split("_").map(&:capitalize).join
      end
    end
  end
end
