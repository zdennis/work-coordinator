# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Adapters::SqliteWorkItemRepository do
  subject(:repo) { described_class.new }

  def build_work_item(overrides = {})
    build(:work_item_domain, **overrides)
  end

  describe "#find_all with project_id filter" do
    let(:project_id) { "proj-abc" }

    it "returns only work items belonging to the given project" do
      repo.save(build_work_item(project_id: project_id))
      repo.save(build_work_item(project_id: "other-proj"))
      repo.save(build_work_item(project_id: nil))

      result = repo.find_all(project_id: project_id)
      expect(result.length).to eq(1)
      expect(result.first.project_id).to eq(project_id)
    end

    it "returns all work items when project_id is nil" do
      repo.save(build_work_item(project_id: project_id))
      repo.save(build_work_item(project_id: nil))

      expect(repo.find_all(project_id: nil).length).to eq(2)
    end
  end

  describe "project_id round-trip" do
    it "persists and retrieves project_id" do
      item = build_work_item(project_id: "proj-xyz")
      repo.save(item)

      found = repo.find(item.id)
      expect(found.project_id).to eq("proj-xyz")
    end

    it "preserves nil project_id" do
      item = build_work_item(project_id: nil)
      repo.save(item)

      expect(repo.find(item.id).project_id).to be_nil
    end
  end

  describe "#find_all with state filter" do
    it "uses the state: keyword (not status:)" do
      repo.save(build_work_item(state: :active))
      repo.save(build_work_item(state: :created))

      result = repo.find_all(state: :active)
      expect(result.map(&:state)).to all(eq(:active))
    end
  end
end
