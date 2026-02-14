# frozen_string_literal: true

require "yaml"
require "fileutils"

module Rwm
  class Overcommit
    RWM_HOOKS = {
      "PrePush" => {
        "CustomScript" => {
          "enabled" => true
        }
      },
      "PostCommit" => {
        "CustomScript" => {
          "enabled" => true
        }
      }
    }.freeze

    PRE_PUSH_SCRIPT = <<~BASH
      #!/bin/bash
      bundle exec rwm check
    BASH

    POST_COMMIT_SCRIPT = <<~BASH
      #!/bin/bash
      # Only rebuild graph if a Gemfile changed in this commit
      if git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | grep -q 'Gemfile'; then
        bundle exec rwm graph
      fi
    BASH

    def initialize(workspace_root)
      @root = workspace_root
    end

    # Sets up overcommit: installs hooks, configures .overcommit.yml,
    # creates hook scripts, and signs the config.
    # Returns true if overcommit was installed successfully.
    def setup
      configure_hooks
      create_hook_scripts
      installed = install_hooks
      sign_config if installed
      installed
    end

    private

    def install_hooks
      system("bundle", "exec", "overcommit", "--install", chdir: @root,
             out: File::NULL, err: File::NULL)
    end

    def sign_config
      system("bundle", "exec", "overcommit", "--sign", chdir: @root,
             out: File::NULL, err: File::NULL)
    end

    def configure_hooks
      config_path = File.join(@root, ".overcommit.yml")

      existing = if File.exist?(config_path)
                   YAML.safe_load(File.read(config_path)) || {}
                 else
                   {}
                 end

      merged = deep_merge(existing, RWM_HOOKS)
      File.write(config_path, YAML.dump(merged))
    end

    def create_hook_scripts
      create_script("pre_push", "rwm_check", PRE_PUSH_SCRIPT)
      create_script("post_commit", "rwm_graph", POST_COMMIT_SCRIPT)
    end

    def create_script(hook_dir, name, content)
      dir = File.join(@root, ".git-hooks", hook_dir)
      FileUtils.mkdir_p(dir)
      path = File.join(dir, name)
      File.write(path, content)
      File.chmod(0o755, path)
    end

    def deep_merge(base, override)
      result = base.dup
      override.each do |key, value|
        if result[key].is_a?(Hash) && value.is_a?(Hash)
          result[key] = deep_merge(result[key], value)
        else
          result[key] = value
        end
      end
      result
    end
  end
end
