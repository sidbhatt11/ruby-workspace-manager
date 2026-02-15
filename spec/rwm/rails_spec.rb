# frozen_string_literal: true

require "spec_helper"
require "rwm/rails"

RSpec.describe "Rwm.require_libs" do
  before { Rwm.resolved_libs.clear }

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
end
