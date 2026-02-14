# frozen_string_literal: true

module Rwm
  class ConventionChecker
    def initialize(graph)
      @graph = graph
    end

    def check!
      violations = []
      violations.concat(check_no_lib_depends_on_app)
      violations.concat(check_no_app_depends_on_app)
      violations.concat(check_no_cycles)

      raise ConventionError, violations unless violations.empty?

      true
    end

    def check
      check!
      []
    rescue ConventionError => e
      e.violations
    end

    private

    def check_no_lib_depends_on_app
      violations = []

      @graph.packages.each do |name, pkg|
        next unless pkg.lib?

        @graph.dependencies(name).each do |dep_name|
          dep = @graph.packages[dep_name]
          next unless dep&.app?

          violations << "lib '#{name}' depends on app '#{dep_name}' — libs cannot depend on apps"
        end
      end

      violations
    end

    def check_no_app_depends_on_app
      violations = []

      @graph.packages.each do |name, pkg|
        next unless pkg.app?

        @graph.dependencies(name).each do |dep_name|
          dep = @graph.packages[dep_name]
          next unless dep&.app?

          violations << "app '#{name}' depends on app '#{dep_name}' — apps cannot depend on other apps"
        end
      end

      violations
    end

    def check_no_cycles
      @graph.topological_order
      []
    rescue CycleError => e
      e.cycles.map { |c| "Dependency cycle: #{c}" }
    end
  end
end
