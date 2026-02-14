# frozen_string_literal: true

require_relative "rwm/version"
require_relative "rwm/errors"

module Rwm
  autoload :Workspace,         "rwm/workspace"
  autoload :Package,           "rwm/package"
  autoload :GemfileParser,     "rwm/gemfile_parser"
  autoload :DependencyGraph,   "rwm/dependency_graph"
  autoload :ConventionChecker, "rwm/convention_checker"
  autoload :CLI,               "rwm/cli"
end
