# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::DependencyGraph do
  let(:auth)    { Rwm::Package.new(name: "auth", path: "/tmp/libs/auth", type: :lib) }
  let(:billing) { Rwm::Package.new(name: "billing", path: "/tmp/libs/billing", type: :lib) }
  let(:api)     { Rwm::Package.new(name: "api", path: "/tmp/apps/api", type: :app) }

  def build_graph
    graph = described_class.new
    graph.add_package(auth)
    graph.add_package(billing)
    graph.add_package(api)
    graph.add_edge("billing", "auth")
    graph.add_edge("api", "auth")
    graph.add_edge("api", "billing")
    graph
  end

  describe "#dependencies" do
    it "returns direct dependencies" do
      graph = build_graph
      expect(graph.dependencies("api")).to contain_exactly("auth", "billing")
      expect(graph.dependencies("billing")).to eq(["auth"])
      expect(graph.dependencies("auth")).to be_empty
    end
  end

  describe "#direct_dependents" do
    it "returns packages that depend on the given package" do
      graph = build_graph
      expect(graph.direct_dependents("auth")).to contain_exactly("billing", "api")
      expect(graph.direct_dependents("billing")).to eq(["api"])
      expect(graph.direct_dependents("api")).to be_empty
    end
  end

  describe "#transitive_dependents" do
    it "returns all transitive dependents" do
      graph = build_graph
      expect(graph.transitive_dependents("auth")).to contain_exactly("billing", "api")
    end

    it "returns empty for packages with no dependents" do
      graph = build_graph
      expect(graph.transitive_dependents("api")).to be_empty
    end
  end

  describe "#topological_order" do
    it "returns packages in dependency order" do
      graph = build_graph
      order = graph.topological_order

      expect(order.index("auth")).to be < order.index("billing")
      expect(order.index("auth")).to be < order.index("api")
      expect(order.index("billing")).to be < order.index("api")
    end
  end

  describe "#execution_levels" do
    it "groups packages by execution level" do
      graph = build_graph
      levels = graph.execution_levels

      expect(levels[0]).to eq(["auth"])
      expect(levels[1]).to eq(["billing"])
      expect(levels[2]).to eq(["api"])
    end

    it "groups independent packages at the same level" do
      graph = described_class.new
      a = Rwm::Package.new(name: "a", path: "/tmp/libs/a", type: :lib)
      b = Rwm::Package.new(name: "b", path: "/tmp/libs/b", type: :lib)
      c = Rwm::Package.new(name: "c", path: "/tmp/apps/c", type: :app)
      graph.add_package(a)
      graph.add_package(b)
      graph.add_package(c)
      graph.add_edge("c", "a")
      graph.add_edge("c", "b")

      levels = graph.execution_levels
      expect(levels[0]).to contain_exactly("a", "b")
      expect(levels[1]).to eq(["c"])
    end

    it "returns empty for empty graph" do
      graph = described_class.new
      expect(graph.execution_levels).to be_empty
    end
  end

  describe "#to_dot" do
    it "returns a valid DOT digraph" do
      graph = build_graph
      dot = graph.to_dot("/tmp")

      expect(dot).to include("digraph rwm {")
      expect(dot).to include("rankdir=LR;")
      expect(dot).to include('"auth" [label="auth (lib)"];')
      expect(dot).to include('"billing" [label="billing (lib)"];')
      expect(dot).to include('"api" [label="api (app)"];')
      expect(dot).to include('"billing" -> "auth";')
      expect(dot).to include('"api" -> "auth";')
      expect(dot).to include('"api" -> "billing";')
      expect(dot).to include("}")
    end
  end

  describe "#to_mermaid" do
    it "returns a valid Mermaid flowchart" do
      graph = build_graph
      mermaid = graph.to_mermaid("/tmp")

      expect(mermaid).to include("graph LR")
      expect(mermaid).to include('auth["auth (lib)"]')
      expect(mermaid).to include('billing["billing (lib)"]')
      expect(mermaid).to include('api["api (app)"]')
      expect(mermaid).to include("billing --> auth")
      expect(mermaid).to include("api --> auth")
      expect(mermaid).to include("api --> billing")
    end
  end

  describe "JSON serialization" do
    it "saves and produces valid JSON structure" do
      Dir.mktmpdir do |dir|
        graph = build_graph
        path = File.join(dir, ".rwm", "graph.json")
        graph.save(path, "/tmp")

        data = JSON.parse(File.read(path))
        expect(data["version"]).to eq(1)
        expect(data["packages"]).to have_key("auth")
        expect(data["edges"]["api"]).to contain_exactly("auth", "billing")
      end
    end
  end
end
