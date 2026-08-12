# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Domain::Project do
  let(:attrs) do
    {
      id: "abc-123",
      name: "my-service",
      alias: "MS",
      workspace_name: "my-service",
      is_default: false,
      created_at: Time.now,
      updated_at: Time.now
    }
  end

  it "can be instantiated with all fields" do
    project = described_class.new(**attrs)
    expect(project.id).to eq("abc-123")
    expect(project.name).to eq("my-service")
    expect(project.alias).to eq("MS")
    expect(project.workspace_name).to eq("my-service")
    expect(project.is_default).to be(false)
  end

  it "allows nil for optional fields" do
    project = described_class.new(**attrs, alias: nil, workspace_name: nil)
    expect(project.alias).to be_nil
    expect(project.workspace_name).to be_nil
  end

  it "is frozen (Data.define semantics)" do
    project = described_class.new(**attrs)
    expect(project).to be_frozen
  end

  it "produces a new instance with updated fields via with" do
    original = described_class.new(**attrs)
    updated  = original.with(is_default: true)

    expect(updated.is_default).to be(true)
    expect(updated.name).to eq(original.name)
    expect(updated).not_to equal(original)
  end
end
