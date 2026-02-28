# frozen_string_literal: true

require "spec_helper"

RSpec.describe "ruby_workspace_manager entry point" do
  it "loads without error" do
    expect { require "ruby_workspace_manager" }.not_to raise_error
  end

  it "makes Rwm module available" do
    require "ruby_workspace_manager"
    expect(defined?(Rwm)).to eq("constant")
  end

  it "makes Rwm.resolved_libs available" do
    require "ruby_workspace_manager"
    expect(Rwm.resolved_libs).to be_a(Set)
  end
end
