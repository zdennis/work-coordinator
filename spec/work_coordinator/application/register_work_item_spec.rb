# frozen_string_literal: true

require "work_coordinator/adapters/in_memory_work_item_repository"

RSpec.describe WorkCoordinator::Application::RegisterWorkItem do
  subject(:register) { described_class.new(work_item_repo: repo, event_store: event_store) }

  let(:repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }

  describe "#call" do
    it "returns a work item in the created state" do
      work_item = register.call(title: "Fix login", kind: :jira)

      expect(work_item).to have_attributes(title: "Fix login", kind: :jira, state: :created, phase: nil)
    end

    it "assigns a uuid" do
      work_item = register.call(title: "Fix login", kind: :jira)

      expect(work_item.id).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "gives each work item a distinct id" do
      first = register.call(title: "One", kind: :chore)
      second = register.call(title: "Two", kind: :chore)

      expect(first.id).not_to eq(second.id)
    end

    it "persists the work item so it can be found again" do
      work_item = register.call(title: "Fix login", kind: :jira)

      expect(repo.find(work_item.id)).to eq(work_item)
    end

    it "records the optional attributes when given" do
      work_item = register.call(title: "Fix login", kind: :jira, external_reference: "ABC-123",
                                repository: "acme/app", workspace_name: "acme-abc-123")

      expect(work_item).to have_attributes(external_reference: "ABC-123", repository: "acme/app",
                                           workspace_name: "acme-abc-123")
    end

    it "leaves the optional attributes nil when omitted" do
      work_item = register.call(title: "Tidy up", kind: :chore)

      expect(work_item).to have_attributes(external_reference: nil, repository: nil, workspace_name: nil)
    end

    it "stamps created_at and updated_at identically" do
      work_item = register.call(title: "Fix login", kind: :jira)

      expect(work_item.created_at).to eq(work_item.updated_at)
    end

    it "appends a work_item.created event" do
      work_item = register.call(title: "Fix login", kind: :jira, external_reference: "ABC-123")

      expect(event_store.all.last).to have_attributes(
        type: "work_item.created",
        work_item_id: work_item.id,
        source: "system",
        data: { title: "Fix login", kind: :jira, external_reference: "ABC-123", project_id: nil }
      )
    end

    it "appends exactly one event per registration" do
      register.call(title: "One", kind: :chore)
      register.call(title: "Two", kind: :chore)

      expect(event_store.all.size).to eq(2)
    end
  end
end
