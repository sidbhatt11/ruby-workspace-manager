# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::ConventionChecker do
  def make_graph(packages, edges)
    graph = Rwm::DependencyGraph.new
    packages.each { |p| graph.add_package(p) }
    edges.each { |from, to| graph.add_edge(from, to) }
    graph
  end

  let(:auth)    { Rwm::Package.new(name: "auth", path: "/tmp/libs/auth", type: :lib) }
  let(:billing) { Rwm::Package.new(name: "billing", path: "/tmp/libs/billing", type: :lib) }
  let(:api)     { Rwm::Package.new(name: "api", path: "/tmp/apps/api", type: :app) }
  let(:web)     { Rwm::Package.new(name: "web", path: "/tmp/apps/web", type: :app) }

  it "passes for valid dependency graph" do
    graph = make_graph([auth, billing, api], [["billing", "auth"], ["api", "billing"]])
    checker = described_class.new(graph)
    expect(checker.check).to be_empty
  end

  it "detects lib depending on app" do
    graph = make_graph([auth, api], [["auth", "api"]])
    checker = described_class.new(graph)
    violations = checker.check

    expect(violations.size).to eq(1)
    expect(violations.first).to include("lib 'auth' depends on app 'api'")
  end

  it "detects app depending on app" do
    graph = make_graph([api, web], [["api", "web"]])
    checker = described_class.new(graph)
    violations = checker.check

    expect(violations.size).to eq(1)
    expect(violations.first).to include("app 'api' depends on app 'web'")
  end

  it "check! raises ConventionError on violations" do
    graph = make_graph([auth, api], [["auth", "api"]])
    checker = described_class.new(graph)

    expect { checker.check! }.to raise_error(Rwm::ConventionError)
  end

  it "check! returns true when no violations" do
    graph = make_graph([auth, api], [["api", "auth"]])
    checker = described_class.new(graph)

    expect(checker.check!).to be true
  end

  it "ignores edges referencing unknown packages" do
    graph = make_graph([auth], [["auth", "unknown_dep"]])
    checker = described_class.new(graph)

    expect(checker.check).to be_empty
  end

  it "detects cyclic dependencies" do
    graph = make_graph([auth, billing], [["auth", "billing"], ["billing", "auth"]])
    checker = described_class.new(graph)
    violations = checker.check

    expect(violations).not_to be_empty
    expect(violations.first).to include("Dependency cycle")
  end

  it "ignores app edges referencing unknown packages" do
    graph = make_graph([api], [["api", "unknown_dep"]])
    checker = described_class.new(graph)

    expect(checker.check).to be_empty
  end
end
