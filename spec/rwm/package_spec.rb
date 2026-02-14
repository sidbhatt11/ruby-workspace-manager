# frozen_string_literal: true

require "spec_helper"

RSpec.describe Rwm::Package do
  describe "#lib? / #app?" do
    it "returns true for lib type" do
      pkg = described_class.new(name: "auth", path: "/tmp/libs/auth", type: :lib)
      expect(pkg).to be_lib
      expect(pkg).not_to be_app
    end

    it "returns true for app type" do
      pkg = described_class.new(name: "api", path: "/tmp/apps/api", type: :app)
      expect(pkg).to be_app
      expect(pkg).not_to be_lib
    end
  end

  describe "#has_rakefile?" do
    it "returns true when Rakefile exists" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "Rakefile"), "task :spec do; end")
        pkg = described_class.new(name: "test", path: dir, type: :lib)
        expect(pkg.has_rakefile?).to be true
      end
    end

    it "returns false when Rakefile is missing" do
      Dir.mktmpdir do |dir|
        pkg = described_class.new(name: "test", path: dir, type: :lib)
        expect(pkg.has_rakefile?).to be false
      end
    end
  end

  describe "#relative_path" do
    it "returns path relative to workspace root" do
      pkg = described_class.new(name: "auth", path: "/workspace/libs/auth", type: :lib)
      expect(pkg.relative_path("/workspace")).to eq("libs/auth")
    end
  end

  describe "equality" do
    it "considers packages with same name and path equal" do
      a = described_class.new(name: "auth", path: "/tmp/libs/auth", type: :lib)
      b = described_class.new(name: "auth", path: "/tmp/libs/auth", type: :lib)
      expect(a).to eq(b)
    end

    it "considers packages with different names not equal" do
      a = described_class.new(name: "auth", path: "/tmp/libs/auth", type: :lib)
      b = described_class.new(name: "billing", path: "/tmp/libs/billing", type: :lib)
      expect(a).not_to eq(b)
    end
  end
end
