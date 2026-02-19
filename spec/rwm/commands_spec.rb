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
        expect(text).to include("1 skipped")
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
        expect(text).to include("1 skipped")
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
  end
end
