# frozen_string_literal: true

require_relative "rwm/version"
require_relative "rwm/errors"

module Rwm
  autoload :Workspace,         "rwm/workspace"
  autoload :Package,           "rwm/package"
  autoload :GemfileParser,     "rwm/gemfile_parser"
  autoload :DependencyGraph,   "rwm/dependency_graph"
  autoload :ConventionChecker, "rwm/convention_checker"
  autoload :TaskRunner,        "rwm/task_runner"
  autoload :AffectedDetector,  "rwm/affected_detector"
  autoload :TaskCache,         "rwm/task_cache"
  autoload :Overcommit,        "rwm/overcommit"
  autoload :CLI,               "rwm/cli"
end
