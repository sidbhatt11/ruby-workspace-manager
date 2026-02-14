# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Rwm::VscodeWorkspace do
  describe "#file_path" do
    it "uses the directory basename for the filename" do
      ws = described_class.new("/home/user/my-project")
      expect(ws.file_path).to eq("/home/user/my-project/my-project.code-workspace")
    end
  end

  describe "#generate" do
    it "creates file with only root folder when packages is empty" do
      Dir.mktmpdir("test-workspace") do |dir|
        ws = described_class.new(dir)
        ws.generate([])

        data = JSON.parse(File.read(ws.file_path))
        expect(data["folders"]).to eq([{ "path" => "." }])
        expect(data["settings"]).to eq({})
      end
    end

    it "creates file with all packages — libs first, then apps, sorted" do
      Dir.mktmpdir("test-workspace") do |dir|
        FileUtils.mkdir_p(File.join(dir, "libs", "billing"))
        FileUtils.mkdir_p(File.join(dir, "libs", "auth"))
        FileUtils.mkdir_p(File.join(dir, "apps", "web"))
        FileUtils.mkdir_p(File.join(dir, "apps", "api"))

        packages = [
          Rwm::Package.new(name: "web", path: File.join(dir, "apps", "web"), type: :app),
          Rwm::Package.new(name: "billing", path: File.join(dir, "libs", "billing"), type: :lib),
          Rwm::Package.new(name: "api", path: File.join(dir, "apps", "api"), type: :app),
          Rwm::Package.new(name: "auth", path: File.join(dir, "libs", "auth"), type: :lib)
        ]

        ws = described_class.new(dir)
        ws.generate(packages)

        data = JSON.parse(File.read(ws.file_path))
        paths = data["folders"].map { |f| f["path"] }
        expect(paths).to eq([".", "libs/auth", "libs/billing", "apps/api", "apps/web"])
      end
    end

    it "preserves existing settings, extensions, launch, and tasks on update" do
      Dir.mktmpdir("test-workspace") do |dir|
        ws = described_class.new(dir)

        existing = {
          "folders" => [{ "path" => "." }],
          "settings" => { "editor.tabSize" => 2 },
          "extensions" => { "recommendations" => ["rebornix.ruby"] },
          "launch" => { "version" => "0.2.0", "configurations" => [] },
          "tasks" => { "version" => "2.0.0", "tasks" => [] }
        }
        File.write(ws.file_path, JSON.pretty_generate(existing))

        FileUtils.mkdir_p(File.join(dir, "libs", "auth"))
        packages = [
          Rwm::Package.new(name: "auth", path: File.join(dir, "libs", "auth"), type: :lib)
        ]

        ws.generate(packages)

        data = JSON.parse(File.read(ws.file_path))
        expect(data["folders"].map { |f| f["path"] }).to eq([".", "libs/auth"])
        expect(data["settings"]).to eq({ "editor.tabSize" => 2 })
        expect(data["extensions"]).to eq({ "recommendations" => ["rebornix.ruby"] })
        expect(data["launch"]).to eq({ "version" => "0.2.0", "configurations" => [] })
        expect(data["tasks"]).to eq({ "version" => "2.0.0", "tasks" => [] })
      end
    end

    it "handles corrupted existing file gracefully" do
      Dir.mktmpdir("test-workspace") do |dir|
        ws = described_class.new(dir)
        File.write(ws.file_path, "not valid json{{{")

        ws.generate([])

        data = JSON.parse(File.read(ws.file_path))
        expect(data["folders"]).to eq([{ "path" => "." }])
        expect(data["settings"]).to eq({})
      end
    end
  end
end
