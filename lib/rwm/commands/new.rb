# frozen_string_literal: true

require "fileutils"
require "optparse"

module Rwm
  module Commands
    class New
      VALID_TEST_FRAMEWORKS = %w[rspec minitest none].freeze

      def initialize(argv)
        @argv = argv
        @test_framework = "rspec"
        parse_options
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

      def parse_options
        OptionParser.new do |opts|
          opts.on("--test=FRAMEWORK", VALID_TEST_FRAMEWORKS, "Test framework (#{VALID_TEST_FRAMEWORKS.join(', ')})") do |fw|
            @test_framework = fw
          end
        end.parse!(@argv)
      end

      def scaffold(pkg_path, name, type)
        source_dir = type == "lib" ? "lib" : "app"
        FileUtils.mkdir_p(File.join(pkg_path, source_dir, name))

        write_gemfile(pkg_path, name)
        write_gemspec(pkg_path, name, type)
        write_rakefile(pkg_path, name)
        write_entry_file(pkg_path, name, type)

        case @test_framework
        when "rspec"
          FileUtils.mkdir_p(File.join(pkg_path, "spec"))
          write_spec_helper(pkg_path)
        when "minitest"
          FileUtils.mkdir_p(File.join(pkg_path, "test"))
          write_test_helper(pkg_path)
        end
      end

      def write_gemfile(pkg_path, name)
        test_gem_line = case @test_framework
                        when "rspec"    then '  gem "rspec"'
                        when "minitest" then '  gem "minitest"'
                        end

        lines = [
          '# frozen_string_literal: true',
          '',
          'source "https://rubygems.org"',
          '',
          'gemspec',
          '',
          'group :development, :test do',
          '  gem "rake"',
        ]
        lines << test_gem_line if test_gem_line
        lines.concat([
          '  gem "ruby_workspace_manager"',
          'end',
          '',
          'require "rwm/gemfile"',
          '# rwm_lib "some_dependency"',
          '',
        ])

        File.write(File.join(pkg_path, "Gemfile"), lines.join("\n"))
      end

      def write_gemspec(pkg_path, name, type)
        lines = [
          '# frozen_string_literal: true',
          '',
          'Gem::Specification.new do |spec|',
          "  spec.name = \"#{name}\"",
          '  spec.version = "0.1.0"',
          '  spec.authors = ["TODO: Your name"]',
          "  spec.summary = \"TODO: Summary of #{name}\"",
          '',
        ]
        lines << '  spec.files = Dir.glob("lib/**/*")' if type == "lib"
        source_dir = type == "lib" ? "lib" : "app"
        lines.concat([
          "  spec.require_paths = [\"#{source_dir}\"]",
          '  spec.required_ruby_version = ">= 3.4.0"',
          'end',
          '',
        ])
        File.write(File.join(pkg_path, "#{name}.gemspec"), lines.join("\n"))
      end

      def write_rakefile(pkg_path, name)
        lines = [
          '# frozen_string_literal: true',
          '',
          'require "rwm/rake"',
          '',
        ]

        case @test_framework
        when "rspec"
          lines.concat([
            'cacheable_task :spec do',
            '  sh "bundle exec rspec"',
            'end',
            '',
          ])
        when "minitest"
          lines.concat([
            'cacheable_task :test do',
            '  sh "bundle exec ruby -Ilib:test -e \'Dir.glob(\"test/**/*_test.rb\").each { |f| require_relative f }\'"',
            'end',
            '',
          ])
        end

        lines.concat([
          "task :bootstrap do",
          "  puts \"Add bootstrap steps for #{name} here.\"",
          "end",
          "",
        ])

        if @test_framework != "none"
          task_name = @test_framework == "rspec" ? ":spec" : ":test"
          lines << "task default: #{task_name}"
          lines << ""
        end

        File.write(File.join(pkg_path, "Rakefile"), lines.join("\n"))
      end

      def write_entry_file(pkg_path, name, type)
        source_dir = type == "lib" ? "lib" : "app"
        File.write(File.join(pkg_path, source_dir, "#{name}.rb"), <<~RUBY)
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

      def write_test_helper(pkg_path)
        File.write(File.join(pkg_path, "test", "test_helper.rb"), <<~RUBY)
          # frozen_string_literal: true

          require "minitest/autorun"
        RUBY
      end

      def camelize(name)
        name.split("_").map(&:capitalize).join
      end
    end
  end
end
