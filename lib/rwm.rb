# frozen_string_literal: true

require_relative "rwm/version"
require_relative "rwm/errors"

module Rwm
  @verbose = false

  def self.verbose?
    @verbose
  end

  def self.verbose=(value)
    @verbose = value
  end

  def self.debug(msg)
    $stderr.puts "[rwm debug] #{msg}" if @verbose
  end

  # Environment hash that points BUNDLE_GEMFILE at a specific directory's Gemfile.
  # Pass as the first argument to Open3.capture3 or system() when spawning
  # bundle commands in package directories, so the child process resolves
  # against the package's Gemfile instead of inheriting the root's.
  def self.bundle_env(dir)
    { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile") }
  end

  autoload :Workspace,         "rwm/workspace"
  autoload :Package,           "rwm/package"
  autoload :GemfileParser,     "rwm/gemfile_parser"
  autoload :DependencyGraph,   "rwm/dependency_graph"
  autoload :ConventionChecker, "rwm/convention_checker"
  autoload :TaskRunner,        "rwm/task_runner"
  autoload :AffectedDetector,  "rwm/affected_detector"
  autoload :TaskCache,         "rwm/task_cache"
  autoload :GitHooks,          "rwm/git_hooks"
  autoload :Overcommit,        "rwm/overcommit"
  autoload :VscodeWorkspace,   "rwm/vscode_workspace"
  autoload :CLI,               "rwm/cli"
end
