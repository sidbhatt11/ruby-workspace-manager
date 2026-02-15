# frozen_string_literal: true

require "spec_helper"
require "rwm/rails"

RSpec.describe "Rwm.require_libs" do
  let(:tmpdir) { Dir.mktmpdir("rwm-rails") }

  before do
    allow(Open3).to receive(:capture3).with("git", "rev-parse", "--show-toplevel")
      .and_return(["#{tmpdir}\n", "", instance_double(Process::Status, success?: true)])
  end

  after { FileUtils.rm_rf(tmpdir) }

  def create_lib(name)
    lib_dir = File.join(tmpdir, "libs", name)
    FileUtils.mkdir_p(lib_dir)
    File.write(File.join(lib_dir, "Gemfile"), "source 'https://rubygems.org'\n")
  end

  it "requires workspace libs that are in the bundle" do
    create_lib("core")
    create_lib("auth")

    required = []
    allow(Rwm).to receive(:require) { |name| required << name }

    Rwm.require_libs

    expect(required).to eq(%w[auth core])
  end

  it "skips libs not in the bundle (LoadError)" do
    create_lib("missing_lib")

    allow(Rwm).to receive(:require).with("missing_lib").and_raise(LoadError)

    expect { Rwm.require_libs }.not_to raise_error
  end

  it "works with empty libs directory" do
    FileUtils.mkdir_p(File.join(tmpdir, "libs"))

    expect { Rwm.require_libs }.not_to raise_error
  end

  it "works when libs directory does not exist" do
    expect { Rwm.require_libs }.not_to raise_error
  end

  it "skips directories without a Gemfile" do
    lib_dir = File.join(tmpdir, "libs", "no_gemfile")
    FileUtils.mkdir_p(lib_dir)

    required = []
    allow(Rwm).to receive(:require) { |name| required << name }

    Rwm.require_libs

    expect(required).not_to include("no_gemfile")
  end

  it "returns nil when not in a git repository" do
    allow(Open3).to receive(:capture3).with("git", "rev-parse", "--show-toplevel")
      .and_return(["", "", instance_double(Process::Status, success?: false)])

    expect { Rwm.require_libs }.not_to raise_error
  end
end
