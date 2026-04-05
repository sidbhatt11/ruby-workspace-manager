# frozen_string_literal: true

require "spec_helper"
require "rwm/rake"

RSpec.describe "cacheable_task DSL" do
  before do
    Rwm::RakeCache.reset!
    Rake::Task.clear
  end

  describe "cacheable_task" do
    it "defines a rake task" do
      cacheable_task(:spec) { }
      expect(Rake::Task.task_defined?(:spec)).to be true
    end

    it "registers the task in RakeCache.declarations" do
      cacheable_task(:spec) { }
      expect(Rwm::RakeCache.declarations).to include("spec" => { "output" => nil })
    end

    it "records output patterns" do
      cacheable_task(:build, output: "pkg/*.gem") { }
      expect(Rwm::RakeCache.declarations["build"]).to eq({ "output" => "pkg/*.gem" })
    end

    it "executes the block when invoked" do
      executed = false
      cacheable_task(:spec) { executed = true }
      Rake::Task[:spec].invoke
      expect(executed).to be true
    end

    it "supports Rake dependency syntax (hash arg)" do
      cacheable_task(:setup) { }
      cacheable_task(seed: :setup) { }

      expect(Rake::Task.task_defined?(:seed)).to be true
      expect(Rake::Task[:seed].prerequisites).to include("setup")
      expect(Rwm::RakeCache.declarations).to include("seed" => { "output" => nil })
    end

    it "supports hash-rocket dependency syntax" do
      cacheable_task(:setup) { }
      cacheable_task(:seed => [:setup]) { }

      expect(Rake::Task.task_defined?(:seed)).to be true
      expect(Rake::Task[:seed].prerequisites).to include("setup")
    end

    it "supports output option with dependency syntax" do
      cacheable_task(:setup) { }
      cacheable_task(seed: :setup, output: "db/seed.log") { }

      expect(Rwm::RakeCache.declarations["seed"]).to eq({ "output" => "db/seed.log" })
      expect(Rake::Task[:seed].prerequisites).to include("setup")
    end

    it "replaces existing task actions instead of stacking" do
      first_ran = false
      second_ran = false

      Rake::Task.define_task(:spec) { first_ran = true }
      cacheable_task(:spec) { second_ran = true }

      Rake::Task[:spec].invoke
      expect(first_ran).to be false
      expect(second_ran).to be true
    end

    it "preserves existing task prerequisites when replacing actions" do
      Rake::Task.define_task(:setup) { }
      Rake::Task.define_task(spec: :setup) { }

      cacheable_task(:spec) { }

      expect(Rake::Task[:spec].prerequisites).to include("setup")
    end
  end

  describe "rwm:cache_config task" do
    it "outputs declarations as JSON" do
      cacheable_task(:spec) { }
      cacheable_task(:build, output: "pkg/*.gem") { }

      output = StringIO.new
      $stdout = output
      Rake::Task["rwm:cache_config"].invoke
      $stdout = STDOUT

      parsed = JSON.parse(output.string)
      expect(parsed).to eq({
        "spec" => { "output" => nil },
        "build" => { "output" => "pkg/*.gem" }
      })
    end
  end
end
