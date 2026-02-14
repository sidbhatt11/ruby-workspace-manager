# frozen_string_literal: true

require "fileutils"

module Rwm
  class GitHooks
    PRE_PUSH_HOOK = <<~BASH
      #!/bin/bash
      bundle exec rwm check
    BASH

    POST_COMMIT_HOOK = <<~BASH
      #!/bin/bash
      # Only rebuild graph if a Gemfile changed in this commit
      if git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep -q 'Gemfile'; then
        bundle exec rwm graph
      fi
    BASH

    def initialize(workspace_root)
      @root = workspace_root
    end

    def setup
      hooks_dir = File.join(@root, ".git", "hooks")
      return false unless File.directory?(File.join(@root, ".git"))

      FileUtils.mkdir_p(hooks_dir)
      install_hook(hooks_dir, "pre-push", PRE_PUSH_HOOK)
      install_hook(hooks_dir, "post-commit", POST_COMMIT_HOOK)
      true
    end

    private

    def install_hook(hooks_dir, name, content)
      path = File.join(hooks_dir, name)

      if File.exist?(path)
        existing = File.read(path)
        return if existing.include?("bundle exec rwm")
        # Append to existing hook
        File.open(path, "a") do |f|
          f.puts
          f.puts "# rwm hooks"
          f.puts content.lines.drop(1).join # skip shebang
        end
      else
        File.write(path, content)
      end

      File.chmod(0o755, path)
    end
  end
end
