# frozen_string_literal: true

require_relative "lib/rwm/version"

Gem::Specification.new do |spec|
  spec.name = "rwm"
  spec.version = Rwm::VERSION
  spec.authors = ["Siddharth Bhatt"]
  spec.summary = "Ruby Workspace Manager — an Nx-like monorepo tool for Ruby"
  spec.description = "Convention-over-configuration monorepo tool for Ruby. " \
                     "Manages dependency graphs, runs tasks in parallel, " \
                     "detects affected packages, and enforces structural conventions."
  spec.homepage = "https://github.com/sidbhatt11/ruby-workspace-manager"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.glob("{bin,lib}/**/*") + %w[LICENSE.txt README.md]
  spec.bindir = "bin"
  spec.executables = ["rwm"]
  spec.require_paths = ["lib"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
end
