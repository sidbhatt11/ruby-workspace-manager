# frozen_string_literal: true

module Rwm
  class Error < StandardError; end

  class WorkspaceNotFoundError < Error
    def initialize
      super("Could not find .rwm/ directory. Are you inside an rwm workspace? Run `rwm init` to create one.")
    end
  end

  class CycleError < Error
    attr_reader :cycles

    def initialize(cycles)
      @cycles = cycles
      super("Dependency cycle detected: #{cycles.map { |c| c.join(" → ") }.join(", ")}")
    end
  end

  class ConventionError < Error
    attr_reader :violations

    def initialize(violations)
      @violations = violations
      super("Convention violations:\n#{violations.map { |v| "  - #{v}" }.join("\n")}")
    end
  end

  class PackageNotFoundError < Error
    def initialize(name)
      super("Package not found: #{name}")
    end
  end

  class PackageExistsError < Error
    def initialize(name)
      super("Package already exists: #{name}")
    end
  end
end
