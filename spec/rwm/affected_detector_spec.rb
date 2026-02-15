# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::AffectedDetector do
  # Helper: set up a git repo with an initial commit, then make changes on a branch
  def setup_git_workspace(dir, packages:, changed_files: {})
    create_fixture_workspace(dir, packages: packages)

    # Initial commit on main
    system("git", "-C", dir, "add", ".", out: File::NULL, err: File::NULL)
    system("git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@test.com",
           "commit", "-m", "initial", "--no-gpg-sign", out: File::NULL, err: File::NULL)

    # Create a feature branch and make changes
    system("git", "-C", dir, "checkout", "-b", "feature", out: File::NULL, err: File::NULL)

    changed_files.each do |path, content|
      full_path = File.join(dir, path)
      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end

    unless changed_files.empty?
      system("git", "-C", dir, "add", ".", out: File::NULL, err: File::NULL)
      system("git", "-C", dir, "-c", "user.name=Test", "-c", "user.email=test@test.com",
             "commit", "-m", "changes", "--no-gpg-sign", out: File::NULL, err: File::NULL)
    end
  end

  describe "#base_branch" do
    it "detects main as base branch" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir, packages: { auth: { type: :lib } })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        expect(detector.base_branch).to eq("main")
      end
    end

    it "uses provided base_branch and skips auto-detection" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir, packages: { auth: { type: :lib } })

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph, base_branch: "develop")

        expect(detector.base_branch).to eq("develop")
      end
    end
  end

  describe "#affected_packages" do
    it "detects directly changed packages" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib }
          },
          changed_files: {
            "libs/auth/lib/auth.rb" => "module Auth; end # changed"
          }
        )

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        affected = detector.affected_packages
        expect(affected.map(&:name)).to include("auth")
        expect(affected.map(&:name)).not_to include("billing")
      end
    end

    it "includes transitive dependents" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib, deps: [:auth] },
            api: { type: :app, deps: [:billing] }
          },
          changed_files: {
            "libs/auth/lib/auth.rb" => "module Auth; end # changed"
          }
        )

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        affected = detector.affected_packages
        expect(affected.map(&:name)).to contain_exactly("auth", "billing", "api")
      end
    end

    it "returns all packages when root-level files change" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib }
          },
          changed_files: {
            "README.md" => "# Changed"
          }
        )

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        affected = detector.affected_packages
        expect(affected.map(&:name)).to contain_exactly("auth", "billing")
      end
    end

    it "detects staged but uncommitted changes" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib }
          },
          changed_files: {}
        )

        # Make a staged change without committing
        File.write(File.join(dir, "libs/auth/lib/auth.rb"), "module Auth; end # staged")
        system("git", "-C", dir, "add", "libs/auth/lib/auth.rb", out: File::NULL, err: File::NULL)

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        affected = detector.affected_packages
        expect(affected.map(&:name)).to include("auth")
        expect(affected.map(&:name)).not_to include("billing")
      end
    end

    it "detects unstaged working directory changes" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib }
          },
          changed_files: {}
        )

        # Make an unstaged change
        File.write(File.join(dir, "libs/billing/lib/billing.rb"), "module Billing; end # dirty")

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        affected = detector.affected_packages
        expect(affected.map(&:name)).to include("billing")
        expect(affected.map(&:name)).not_to include("auth")
      end
    end

    it "returns empty when nothing changed" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: { auth: { type: :lib } },
          changed_files: {}
        )

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        affected = detector.affected_packages
        expect(affected).to be_empty
      end
    end
  end

  describe "committed_only mode" do
    it "ignores staged and unstaged changes" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib }
          },
          changed_files: {}
        )

        # Make staged and unstaged changes
        File.write(File.join(dir, "libs/auth/lib/auth.rb"), "module Auth; end # staged")
        system("git", "-C", dir, "add", "libs/auth/lib/auth.rb", out: File::NULL, err: File::NULL)
        File.write(File.join(dir, "libs/billing/lib/billing.rb"), "module Billing; end # dirty")

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph, committed_only: true)

        affected = detector.affected_packages
        expect(affected).to be_empty
      end
    end
  end

  describe "#directly_changed_packages" do
    it "returns only directly changed packages without dependents" do
      Dir.mktmpdir do |dir|
        setup_git_workspace(dir,
          packages: {
            auth: { type: :lib },
            billing: { type: :lib, deps: [:auth] }
          },
          changed_files: {
            "libs/auth/lib/auth.rb" => "module Auth; end # changed"
          }
        )

        workspace = Rwm::Workspace.find(dir)
        graph = Rwm::DependencyGraph.build(workspace)
        detector = described_class.new(workspace, graph)

        changed = detector.directly_changed_packages
        expect(changed.map(&:name)).to eq(["auth"])
      end
    end
  end
end
