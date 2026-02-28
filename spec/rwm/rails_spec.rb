# frozen_string_literal: true

require "spec_helper"
require "rwm/rails"

RSpec.describe "Rwm.require_libs" do
  before do
    Rwm.resolved_libs.clear
    Rwm.instance_variable_set(:@libs_required, false)
  end

  it "requires only libs registered via rwm_lib" do
    Rwm.resolved_libs.merge(%w[auth core])

    required = []
    allow(Rwm).to receive(:require) { |name| required << name }

    Rwm.require_libs

    expect(required).to match_array(%w[auth core])
  end

  it "does nothing when no libs were resolved" do
    required = []
    allow(Rwm).to receive(:require) { |name| required << name }

    Rwm.require_libs

    expect(required).to be_empty
  end

  it "does not require libs that were not declared via rwm_lib" do
    Rwm.resolved_libs.add("auth")

    required = []
    allow(Rwm).to receive(:require) { |name| required << name }

    Rwm.require_libs

    expect(required).to eq(%w[auth])
    expect(required).not_to include("billing")
  end

  it "is idempotent — second call is a no-op" do
    Rwm.resolved_libs.add("auth")

    required = []
    allow(Rwm).to receive(:require) { |name| required << name }

    Rwm.require_libs
    Rwm.require_libs

    expect(required).to eq(%w[auth])
  end

  it "sets libs_required? to true after first call" do
    allow(Rwm).to receive(:require)

    expect(Rwm.libs_required?).to be false
    Rwm.require_libs
    expect(Rwm.libs_required?).to be true
  end

  it "emits debug output when verbose" do
    Rwm.verbose = true
    Rwm.resolved_libs.add("auth")
    allow(Rwm).to receive(:require)

    expect { Rwm.require_libs }.to output(/required 1 workspace lib/).to_stderr
  ensure
    Rwm.verbose = false
  end
end
