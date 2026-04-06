# frozen_string_literal: true

require "spec_helper"
require "rwm/commands/list"
require "rwm/commands/info"
require "rwm/commands/check"
require "rwm/commands/graph"
require "rwm/commands/new"
require "rwm/commands/cache"
require "rwm/commands/affected"
require "rwm/commands/run"
require "rwm/commands/init"
require "rwm/commands/bootstrap"

# Integration tests for each Rwm::Commands::* class.
# Commands that call Workspace.find (which defaults to Dir.pwd) need Dir.chdir.
RSpec.describe "Commands" do
  # Helper: run inside a temp workspace
  def with_workspace(packages: {}, &block)
    Dir.mktmpdir do |dir|
      create_fixture_workspace(dir, packages: packages)
      Dir.chdir(dir, &block)
    end
  end

  describe Rwm::Commands::List do
    it "lists packages in a table" do
      with_workspace(packages: { auth: { type: :lib }, api: { type: :app, deps: [:auth] } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new([]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("auth")
        expect(text).to include("api")
        expect(text).to include("Name")
      end
    end

    it "prints 'No packages found.' when workspace is empty" do
      with_workspace do
        output = StringIO.new
        $stdout = output

        result = described_class.new([]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("No packages found.")
      end
    end
  end

  describe Rwm::Commands::Info do
    it "shows package details" do
      with_workspace(packages: { auth: { type: :lib } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["auth"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("Package:      auth")
        expect(text).to include("Type:         lib")
        expect(text).to include("Has Rakefile: yes")
      end
    end

    it "returns 1 with no package name" do
      stderr = StringIO.new
      $stderr = stderr

      result = described_class.new([]).run

      $stderr = STDERR
      expect(result).to eq(1)
      expect(stderr.string).to include("Usage:")
    end

    it "raises PackageNotFoundError for unknown package" do
      with_workspace do
        expect { described_class.new(["nope"]).run }.to raise_error(Rwm::PackageNotFoundError)
      end
    end

    it "shows dependencies and dependents" do
      with_workspace(packages: {
        auth: { type: :lib },
        billing: { type: :lib, deps: [:auth] }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["auth"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("Dependents:   billing")
      end
    end

    it "shows 'no' for package without Rakefile" do
      with_workspace(packages: { auth: { type: :lib, rakefile: false } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["auth"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("Has Rakefile: no")
      end
    end

    it "shows transitive dependents when they exceed direct dependents" do
      with_workspace(packages: {
        auth: { type: :lib },
        billing: { type: :lib, deps: [:auth] },
        api: { type: :app, deps: [:billing] }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["auth"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("Dependents:   billing")
        expect(text).to include("Transitive:")
        expect(text).to include("api")
      end
    end
  end

  describe Rwm::Commands::Check do
    it "passes for a valid graph" do
      with_workspace(packages: { auth: { type: :lib }, billing: { type: :lib } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new([]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("All conventions passed.")
      end
    end

    it "reports lib-depends-on-app violation" do
      with_workspace(packages: { api: { type: :app }, auth: { type: :lib, deps: [:api] } }) do
        stderr = StringIO.new
        $stderr = stderr
        $stdout = StringIO.new

        result = described_class.new([]).run

        $stderr = STDERR
        $stdout = STDOUT
        expect(result).to eq(1)
        expect(stderr.string).to include("lib 'auth' depends on app 'api'")
      end
    end
  end

  describe Rwm::Commands::Graph do
    it "saves graph and prints summary" do
      with_workspace(packages: { auth: { type: :lib }, billing: { type: :lib } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new([]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("Graph saved to .rwm/graph.json")
        expect(output.string).to include("2 packages")
        expect(File.exist?(".rwm/graph.json")).to be true
      end
    end

    it "outputs DOT format with --dot" do
      with_workspace(packages: { auth: { type: :lib } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--dot"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("digraph rwm")
        expect(output.string).to include("auth")
      end
    end

    it "outputs Mermaid format with --mermaid" do
      with_workspace(packages: { auth: { type: :lib } }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--mermaid"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("graph LR")
        expect(output.string).to include("auth")
      end
    end

    it "shows lib/ prefix for libs and app/ prefix for apps in default output" do
      with_workspace(packages: { auth: { type: :lib }, api: { type: :app, deps: [:auth] } }) do
        output = StringIO.new
        $stdout = output

        described_class.new([]).run

        $stdout = STDOUT
        expect(output.string).to include("lib/auth")
        expect(output.string).to include("app/api")
        expect(output.string).not_to include("app/auth")
      end
    end
  end

  describe Rwm::Commands::New do
    it "scaffolds a new lib" do
      with_workspace do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["lib", "payments"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("Created lib 'payments'")
        expect(File.directory?("libs/payments/lib/payments")).to be true
        expect(File.directory?("libs/payments/spec")).to be true
        expect(File.exist?("libs/payments/Gemfile")).to be true
        expect(File.exist?("libs/payments/Rakefile")).to be true
        expect(File.exist?("libs/payments/payments.gemspec")).to be true
      end
    end

    it "scaffolds a new app" do
      with_workspace do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["app", "web"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("Created app 'web'")
        expect(File.directory?("apps/web/app/web")).to be true
      end
    end

    it "rejects invalid type" do
      stderr = StringIO.new
      $stderr = stderr

      result = described_class.new(["service", "foo"]).run

      $stderr = STDERR
      expect(result).to eq(1)
      expect(stderr.string).to include("Usage:")
    end

    it "rejects invalid name" do
      stderr = StringIO.new
      $stderr = stderr

      result = described_class.new(["lib", "BadName"]).run

      $stderr = STDERR
      expect(result).to eq(1)
      expect(stderr.string).to include("Package name must start with a lowercase letter")
    end

    it "raises PackageExistsError when package already exists" do
      with_workspace(packages: { auth: { type: :lib } }) do
        expect { described_class.new(["lib", "auth"]).run }.to raise_error(Rwm::PackageExistsError)
      end
    end

    context "with --test=minitest" do
      it "scaffolds with minitest infrastructure" do
        with_workspace do
          output = StringIO.new
          $stdout = output

          result = described_class.new(["--test=minitest", "lib", "payments"]).run

          $stdout = STDOUT
          expect(result).to eq(0)
          expect(File.directory?("libs/payments/test")).to be true
          expect(File.exist?("libs/payments/test/test_helper.rb")).to be true
          expect(File.read("libs/payments/test/test_helper.rb")).to include("minitest/autorun")
          expect(File.read("libs/payments/Gemfile")).to include('"minitest"')
          expect(File.read("libs/payments/Gemfile")).not_to include('"rspec"')
          expect(File.read("libs/payments/Rakefile")).to include("cacheable_task :test")
          expect(File.read("libs/payments/Rakefile")).to include("task default: :test")
          expect(File.directory?("libs/payments/spec")).to be false
        end
      end
    end

    context "with --test=none" do
      it "scaffolds without test infrastructure" do
        with_workspace do
          output = StringIO.new
          $stdout = output

          result = described_class.new(["--test=none", "lib", "payments"]).run

          $stdout = STDOUT
          expect(result).to eq(0)
          expect(File.directory?("libs/payments/spec")).to be false
          expect(File.directory?("libs/payments/test")).to be false
          expect(File.read("libs/payments/Gemfile")).not_to include('"rspec"')
          expect(File.read("libs/payments/Gemfile")).not_to include('"minitest"')
          expect(File.read("libs/payments/Rakefile")).not_to include("cacheable_task")
          expect(File.read("libs/payments/Rakefile")).not_to include("task default:")
        end
      end
    end

    context "with default --test (rspec)" do
      it "scaffolds with rspec infrastructure" do
        with_workspace do
          output = StringIO.new
          $stdout = output

          result = described_class.new(["lib", "payments"]).run

          $stdout = STDOUT
          expect(result).to eq(0)
          expect(File.directory?("libs/payments/spec")).to be true
          expect(File.read("libs/payments/Gemfile")).to include('"rspec"')
          expect(File.read("libs/payments/Rakefile")).to include("cacheable_task :spec")
          expect(File.read("libs/payments/Rakefile")).to include("task default: :spec")
        end
      end
    end
  end

  describe Rwm::Commands::Cache do
    it "cleans all caches" do
      with_workspace(packages: { auth: { type: :lib } }) do
        # Create a fake cache file
        cache_dir = File.join(Dir.pwd, ".rwm", "cache")
        FileUtils.mkdir_p(cache_dir)
        File.write(File.join(cache_dir, "auth-spec"), "abc123")

        output = StringIO.new
        $stdout = output

        result = described_class.new(["clean"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("Cleared all cached task results.")
        expect(Dir.glob(File.join(cache_dir, "*"))).to be_empty
      end
    end

    it "cleans cache for a specific package" do
      with_workspace(packages: { auth: { type: :lib }, billing: { type: :lib } }) do
        cache_dir = File.join(Dir.pwd, ".rwm", "cache")
        FileUtils.mkdir_p(cache_dir)
        File.write(File.join(cache_dir, "auth-spec"), "abc123")
        File.write(File.join(cache_dir, "billing-spec"), "def456")

        output = StringIO.new
        $stdout = output

        result = described_class.new(["clean", "auth"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("Cleared cache for auth.")
        expect(File.exist?(File.join(cache_dir, "auth-spec"))).to be false
        expect(File.exist?(File.join(cache_dir, "billing-spec"))).to be true
      end
    end

    it "returns 1 with no subcommand" do
      stderr = StringIO.new
      $stderr = stderr

      result = described_class.new([]).run

      $stderr = STDERR
      expect(result).to eq(1)
      expect(stderr.string).to include("Usage:")
    end

    it "returns 1 for unknown subcommand" do
      stderr = StringIO.new
      $stderr = stderr

      result = described_class.new(["purge"]).run

      $stderr = STDERR
      expect(result).to eq(1)
      expect(stderr.string).to include("Unknown cache subcommand: purge")
    end
  end

  describe Rwm::Commands::Affected do
    it "shows affected packages" do
      with_workspace(packages: { auth: { type: :lib }, api: { type: :app, deps: [:auth] } }) do
        # Commit so we have a base, then modify a file
        system("git", "-C", Dir.pwd, "add", ".", out: File::NULL, err: File::NULL)
        system("git", "-C", Dir.pwd, "-c", "user.name=Test", "-c", "user.email=t@t.com",
               "commit", "-m", "init", "--no-gpg-sign", out: File::NULL, err: File::NULL)
        File.write("libs/auth/lib/auth.rb", "module Auth; end\n# changed\n")

        output = StringIO.new
        $stdout = output

        result = described_class.new([]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("auth")
      end
    end

    it "prints 'No packages affected.' when nothing changed" do
      with_workspace(packages: { auth: { type: :lib } }) do
        system("git", "-C", Dir.pwd, "add", ".", out: File::NULL, err: File::NULL)
        system("git", "-C", Dir.pwd, "-c", "user.name=Test", "-c", "user.email=t@t.com",
               "commit", "-m", "init", "--no-gpg-sign", out: File::NULL, err: File::NULL)

        output = StringIO.new
        $stdout = output

        result = described_class.new(["--committed"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("No packages affected.")
      end
    end
  end

  describe Rwm::Commands::Run do
    it "returns 1 with no task argument" do
      stderr = StringIO.new
      $stderr = stderr

      result = described_class.new([]).run

      $stderr = STDERR
      expect(result).to eq(1)
      expect(stderr.string).to include("Usage:")
    end

    it "runs a task and shows summary" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--no-cache", "ping"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("1 package(s): 1 passed.")
      end
    end

    it "lists packages with --dry-run without executing" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--dry-run", "--no-cache", "ping"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("Dry run:")
        expect(text).to include("auth")
        expect(text).not_to include("pong")
      end
    end

    it "accepts flags after the task name" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["ping", "--no-cache", "--dry-run"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("Dry run:")
        expect(text).to include("auth")
      end
    end

    it "reports skipped count in summary" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "# no tasks" },
        billing: { type: :lib, rakefile_content: "task :ping do\n  puts 'ok'\nend" }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--no-cache", "ping"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("2 package(s):")
        expect(text).to include("1 passed")
        expect(text).to include("1 skipped (no task)")
      end
    end

    it "reports dependency-skipped packages as skipped, not failed" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  exit 1\nend" },
        api: { type: :app, deps: [:auth], rakefile_content: "task :ping do\n  puts 'ok'\nend" }
      }) do
        output = StringIO.new
        stderr = StringIO.new
        $stdout = output
        $stderr = stderr

        result = described_class.new(["--no-cache", "ping"]).run

        $stdout = STDOUT
        $stderr = STDERR
        expect(result).to eq(1)
        text = output.string + stderr.string
        expect(text).to include("1 failed")
        expect(text).to include("1 skipped (dep failed)")
        # Only auth should be listed as failed, not api
        expect(text).to include("Failed:")
        expect(text).to include("auth")
        expect(text).not_to include("- api")
      end
    end

    it "reports failures in summary" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  exit 1\nend" },
        billing: { type: :lib, rakefile_content: "task :ping do\n  puts 'ok'\nend" }
      }) do
        output = StringIO.new
        stderr = StringIO.new
        $stdout = output
        $stderr = stderr

        result = described_class.new(["--no-cache", "ping"]).run

        $stdout = STDOUT
        $stderr = STDERR
        expect(result).to eq(1)
        text = output.string + stderr.string
        expect(text).to include("1 failed")
        expect(text).to include("Failed:")
      end
    end

    it "runs a task on multiple named packages" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" },
        billing: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" },
        web: { type: :app, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--no-cache", "ping", "auth", "billing"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        text = output.string
        expect(text).to include("2 package(s): 2 passed.")
        expect(text).not_to include("[web]")
      end
    end

    it "errors on non-existent package name" do
      with_workspace(packages: { auth: { type: :lib } }) do
        expect {
          described_class.new(["--no-cache", "ping", "auth", "nope"]).run
        }.to raise_error(Rwm::PackageNotFoundError, /nope/)
      end
    end

    it "errors when --affected and explicit packages are both given" do
      with_workspace(packages: { auth: { type: :lib } }) do
        stderr = StringIO.new
        $stderr = stderr

        result = described_class.new(["--no-cache", "--affected", "ping", "auth"]).run

        $stderr = STDERR
        expect(result).to eq(1)
        expect(stderr.string).to include("mutually exclusive")
      end
    end

    it "deduplicates repeated package names" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
      }) do
        output = StringIO.new
        $stdout = output

        result = described_class.new(["--no-cache", "ping", "auth", "auth"]).run

        $stdout = STDOUT
        expect(result).to eq(0)
        expect(output.string).to include("1 package(s): 1 passed.")
      end
    end

    context "with caching" do
      def stub_cache_declarations(declarations)
        ok_status = instance_double(Process::Status, success?: true)
        json_output = JSON.generate(declarations)
        original_capture3 = Open3.method(:capture3)
        allow(Open3).to receive(:capture3) do |*args, **kwargs|
          if args.include?("rwm:cache_config")
            [json_output, "", ok_status]
          else
            original_capture3.call(*args, **kwargs)
          end
        end
      end

      it "caches a passing task and skips on second run" do
        with_workspace(packages: {
          auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
        }) do
          stub_cache_declarations("ping" => {})

          output1 = StringIO.new
          $stdout = output1
          result1 = described_class.new(["ping"]).run
          $stdout = STDOUT
          expect(result1).to eq(0)
          expect(output1.string).to include("1 passed")

          output2 = StringIO.new
          $stdout = output2
          result2 = described_class.new(["ping"]).run
          $stdout = STDOUT
          expect(result2).to eq(0)
          expect(output2.string).to include("[auth] cached")
          expect(output2.string).to include("All packages cached")
        end
      end

      it "does not store cache for failed tasks" do
        with_workspace(packages: {
          auth: { type: :lib, rakefile_content: "task :ping do\n  exit 1\nend" }
        }) do
          stub_cache_declarations("ping" => {})

          output = StringIO.new
          stderr = StringIO.new
          $stdout = output
          $stderr = stderr
          result = described_class.new(["ping"]).run
          $stdout = STDOUT
          $stderr = STDERR

          expect(result).to eq(1)
          cache_file = File.join(Dir.pwd, ".rwm", "cache", "auth-ping")
          expect(File.exist?(cache_file)).to be false
        end
      end

      it "does not store cache for non-cacheable tasks" do
        with_workspace(packages: {
          auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
        }) do
          stub_cache_declarations({})

          output = StringIO.new
          $stdout = output
          result = described_class.new(["ping"]).run
          $stdout = STDOUT

          expect(result).to eq(0)
          expect(output.string).to include("1 passed")
          cache_file = File.join(Dir.pwd, ".rwm", "cache", "auth-ping")
          expect(File.exist?(cache_file)).to be false
        end
      end
    end

    it "respects --concurrency option" do
      with_workspace(packages: {
        auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
      }) do
        output = StringIO.new
        $stdout = output
        result = described_class.new(["--no-cache", "--concurrency", "1", "ping"]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).to include("1 passed")
      end
    end

    context "with --affected" do
      it "runs only on affected packages" do
        with_workspace(packages: {
          auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" },
          billing: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
        }) do
          system("git", "-C", Dir.pwd, "add", ".", out: File::NULL, err: File::NULL)
          system("git", "-C", Dir.pwd, "-c", "user.name=Test", "-c", "user.email=t@t.com",
                 "commit", "-m", "init", "--no-gpg-sign", out: File::NULL, err: File::NULL)
          File.write("libs/auth/lib/auth.rb", "module Auth; end\n# changed\n")

          output = StringIO.new
          $stdout = output
          result = described_class.new(["--no-cache", "--affected", "ping"]).run
          $stdout = STDOUT

          expect(result).to eq(0)
          text = output.string
          expect(text).to include("Running on")
          expect(text).to include("affected")
        end
      end

      it "returns 0 when no packages are affected" do
        with_workspace(packages: {
          auth: { type: :lib, rakefile_content: "task :ping do\n  puts 'pong'\nend" }
        }) do
          system("git", "-C", Dir.pwd, "add", ".", out: File::NULL, err: File::NULL)
          system("git", "-C", Dir.pwd, "-c", "user.name=Test", "-c", "user.email=t@t.com",
                 "commit", "-m", "init", "--no-gpg-sign", out: File::NULL, err: File::NULL)

          output = StringIO.new
          $stdout = output
          result = described_class.new(["--no-cache", "--affected", "--committed", "ping"]).run
          $stdout = STDOUT

          expect(result).to eq(0)
          expect(output.string).to include("No affected packages")
        end
      end
    end

    it "returns 0 with no packages in workspace" do
      with_workspace do
        output = StringIO.new
        $stdout = output
        result = described_class.new(["--no-cache", "ping"]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).to include("No packages found")
      end
    end

    it "returns 0 when no packages have Rakefiles" do
      with_workspace(packages: { auth: { type: :lib, rakefile: false } }) do
        output = StringIO.new
        $stdout = output
        result = described_class.new(["--no-cache", "ping"]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).to include("No packages with a Rakefile found")
      end
    end
  end

  describe Rwm::Commands::Init do
    it "creates dirs, Gemfile, Rakefile, .gitignore" do
      Dir.mktmpdir do |dir|
        # Need a git repo for bootstrap's Workspace.find
        system("git", "init", "--quiet", "--initial-branch=main", dir, out: File::NULL, err: File::NULL)

        Dir.chdir(dir) do
          output = StringIO.new
          $stdout = output

          # Stub the bootstrap call since it would run bundle install
          allow(Rwm::Commands::Bootstrap).to receive_message_chain(:new, :run).and_return(0)

          result = described_class.new([]).run

          $stdout = STDOUT
          expect(result).to eq(0)
          expect(File.directory?("libs")).to be true
          expect(File.directory?("apps")).to be true
          expect(File.exist?("Gemfile")).to be true
          expect(File.exist?("Rakefile")).to be true
          expect(File.read(".gitignore")).to include(".rwm/")
        end
      end
    end

    it "is idempotent — does not overwrite existing files" do
      Dir.mktmpdir do |dir|
        system("git", "init", "--quiet", "--initial-branch=main", dir, out: File::NULL, err: File::NULL)

        Dir.chdir(dir) do
          File.write("Gemfile", "# custom gemfile\n")
          File.write("Rakefile", "# custom rakefile\n")
          FileUtils.mkdir_p("libs")
          FileUtils.mkdir_p("apps")

          $stdout = StringIO.new
          allow(Rwm::Commands::Bootstrap).to receive_message_chain(:new, :run).and_return(0)
          described_class.new([]).run
          $stdout = STDOUT

          expect(File.read("Gemfile")).to eq("# custom gemfile\n")
          expect(File.read("Rakefile")).to eq("# custom rakefile\n")
        end
      end
    end

    it "generates VSCode workspace with --vscode" do
      Dir.mktmpdir do |dir|
        system("git", "init", "--quiet", "--initial-branch=main", dir, out: File::NULL, err: File::NULL)

        Dir.chdir(dir) do
          $stdout = StringIO.new
          allow(Rwm::Commands::Bootstrap).to receive_message_chain(:new, :run).and_return(0)

          result = described_class.new(["--vscode"]).run

          $stdout = STDOUT
          expect(result).to eq(0)
          basename = File.basename(dir)
          expect(File.exist?("#{basename}.code-workspace")).to be true
        end
      end
    end

    it "initializes at git root even when run from a subdirectory" do
      Dir.mktmpdir do |dir|
        system("git", "init", "--quiet", "--initial-branch=main", dir, out: File::NULL, err: File::NULL)

        subdir = File.join(dir, "some", "nested", "dir")
        FileUtils.mkdir_p(subdir)

        Dir.chdir(subdir) do
          $stdout = StringIO.new
          allow(Rwm::Commands::Bootstrap).to receive_message_chain(:new, :run).and_return(0)

          result = described_class.new([]).run

          $stdout = STDOUT
          expect(result).to eq(0)
          # Structure should be at git root, not in subdirectory
          expect(File.directory?(File.join(dir, "libs"))).to be true
          expect(File.directory?(File.join(dir, "apps"))).to be true
          expect(File.exist?(File.join(dir, "Gemfile"))).to be true
          expect(File.directory?(File.join(subdir, "libs"))).to be false
        end
      end
    end

    it "raises error when not inside a git repository" do
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          expect {
            $stdout = StringIO.new
            described_class.new([]).run
          }.to raise_error(Rwm::Error, /git init/)
          $stdout = STDOUT
        end
      end
    end

    it "does not duplicate .rwm/ in .gitignore" do
      Dir.mktmpdir do |dir|
        system("git", "init", "--quiet", "--initial-branch=main", dir, out: File::NULL, err: File::NULL)

        Dir.chdir(dir) do
          File.write(".gitignore", ".rwm/\n")

          $stdout = StringIO.new
          allow(Rwm::Commands::Bootstrap).to receive_message_chain(:new, :run).and_return(0)
          described_class.new([]).run
          $stdout = STDOUT

          expect(File.read(".gitignore").scan(".rwm/").size).to eq(1)
        end
      end
    end

    it "adds newline before .rwm/ when .gitignore lacks trailing newline" do
      Dir.mktmpdir do |dir|
        system("git", "init", "--quiet", "--initial-branch=main", dir, out: File::NULL, err: File::NULL)

        Dir.chdir(dir) do
          File.write(".gitignore", "node_modules")

          $stdout = StringIO.new
          allow(Rwm::Commands::Bootstrap).to receive_message_chain(:new, :run).and_return(0)
          described_class.new([]).run
          $stdout = STDOUT

          content = File.read(".gitignore")
          expect(content).to eq("node_modules\n.rwm/\n")
        end
      end
    end
  end

  describe Rwm::Commands::Bootstrap do
    def stub_bundle_commands
      ok_status = instance_double(Process::Status, success?: true)
      original_capture3 = Open3.method(:capture3)
      allow(Open3).to receive(:capture3) do |*args, **kwargs|
        if args.any? { |a| a == "bundle" }
          ["", "", ok_status]
        else
          original_capture3.call(*args, **kwargs)
        end
      end
    end

    it "bootstraps workspace with packages" do
      with_workspace(packages: {
        auth: { type: :lib },
        billing: { type: :lib, deps: [:auth] }
      }) do
        stub_bundle_commands

        output = StringIO.new
        $stdout = output
        result = described_class.new([]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        text = output.string
        expect(text).to include("Bootstrap complete!")
        expect(text).to include("Git hooks installed")
        expect(text).to include("All conventions passed")
        expect(File.exist?(".rwm/graph.json")).to be true
      end
    end

    it "bootstraps targeted packages with transitive dependencies" do
      with_workspace(packages: {
        auth: { type: :lib },
        billing: { type: :lib, deps: [:auth] },
        web: { type: :app, deps: [:billing] }
      }) do
        stub_bundle_commands

        output = StringIO.new
        $stdout = output
        result = described_class.new(["billing"]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        text = output.string
        expect(text).to include("2 package(s)")
        expect(text).to include("billing + 1 dependencies")
        expect(text).to include("Bootstrap complete!")
      end
    end

    it "handles empty workspace" do
      with_workspace do
        stub_bundle_commands

        output = StringIO.new
        $stdout = output
        result = described_class.new([]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).to include("No packages found")
      end
    end

    it "raises BootstrapError when bundle install fails" do
      with_workspace(packages: { auth: { type: :lib } }) do
        fail_status = instance_double(Process::Status, success?: false)
        original_capture3 = Open3.method(:capture3)
        allow(Open3).to receive(:capture3) do |*args, **kwargs|
          if args.any? { |a| a == "bundle" }
            ["", "error", fail_status]
          else
            original_capture3.call(*args, **kwargs)
          end
        end

        output = StringIO.new
        $stdout = output
        expect {
          described_class.new([]).run
        }.to raise_error(Rwm::BootstrapError, /bundle install failed/)
        $stdout = STDOUT
      end
    end

    it "runs root-level bundle install and rake bootstrap when files exist" do
      with_workspace(packages: { auth: { type: :lib } }) do
        File.write("Gemfile", "source 'https://rubygems.org'\n")
        File.write("Rakefile", "task :bootstrap do; end\n")
        stub_bundle_commands

        output = StringIO.new
        $stdout = output
        result = described_class.new([]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).to include("bundle install...")
        expect(output.string).to include("rake bootstrap...")
      end
    end

    it "sets up overcommit when .overcommit.yml exists" do
      with_workspace(packages: { auth: { type: :lib } }) do
        File.write(".overcommit.yml", "# overcommit\n")
        stub_bundle_commands
        allow_any_instance_of(Rwm::Overcommit).to receive(:setup).and_return(true)

        output = StringIO.new
        $stdout = output
        result = described_class.new([]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).to include("Overcommit configured")
      end
    end

    it "warns when overcommit setup fails" do
      with_workspace(packages: { auth: { type: :lib } }) do
        File.write(".overcommit.yml", "# overcommit\n")
        stub_bundle_commands
        allow_any_instance_of(Rwm::Overcommit).to receive(:setup).and_return(false)

        output = StringIO.new
        stderr = StringIO.new
        $stdout = output
        $stderr = stderr
        result = described_class.new([]).run
        $stdout = STDOUT
        $stderr = STDERR

        expect(result).to eq(0)
        expect(stderr.string).to include("Could not install overcommit hooks")
        expect(output.string).to include("Hook scripts and config created")
      end
    end

    it "warns when git hooks setup fails" do
      with_workspace(packages: { auth: { type: :lib } }) do
        stub_bundle_commands
        allow_any_instance_of(Rwm::GitHooks).to receive(:setup).and_return(false)

        output = StringIO.new
        stderr = StringIO.new
        $stdout = output
        $stderr = stderr
        result = described_class.new([]).run
        $stdout = STDOUT
        $stderr = STDERR

        expect(result).to eq(0)
        expect(stderr.string).to include("Could not install git hooks")
      end
    end

    it "skips rake bootstrap for packages without Rakefiles" do
      with_workspace(packages: { auth: { type: :lib, rakefile: false } }) do
        stub_bundle_commands

        output = StringIO.new
        $stdout = output
        result = described_class.new([]).run
        $stdout = STDOUT

        expect(result).to eq(0)
        expect(output.string).not_to include("Running bootstrap tasks")
        expect(output.string).to include("Bootstrap complete!")
      end
    end

    it "raises BootstrapError when rake bootstrap fails" do
      with_workspace(packages: { auth: { type: :lib } }) do
        ok_status = instance_double(Process::Status, success?: true)
        fail_status = instance_double(Process::Status, success?: false)
        original_capture3 = Open3.method(:capture3)
        allow(Open3).to receive(:capture3) do |*args, **kwargs|
          if args.any? { |a| a == "bundle" }
            if args.include?("rake") && args.include?("bootstrap") && !args.include?("-T")
              ["", "rake aborted!", fail_status]
            else
              ["", "", ok_status]
            end
          else
            original_capture3.call(*args, **kwargs)
          end
        end

        output = StringIO.new
        $stdout = output
        expect {
          described_class.new([]).run
        }.to raise_error(Rwm::BootstrapError, /rake bootstrap failed/)
        $stdout = STDOUT
      end
    end

    it "prints convention violations as warnings" do
      with_workspace(packages: {
        api: { type: :app },
        auth: { type: :lib, deps: [:api] }
      }) do
        stub_bundle_commands

        output = StringIO.new
        stderr = StringIO.new
        $stdout = output
        $stderr = stderr
        result = described_class.new([]).run
        $stdout = STDOUT
        $stderr = STDERR

        expect(result).to eq(0)
        expect(output.string).to include("Bootstrap complete!")
        expect(stderr.string).to include("Convention violations")
        expect(stderr.string).to include("lib 'auth' depends on app 'api'")
      end
    end
  end
end
