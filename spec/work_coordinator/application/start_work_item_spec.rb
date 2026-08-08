# frozen_string_literal: true

require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_agent_session"

RSpec.describe WorkCoordinator::Application::StartWorkItem do
  subject(:start) do
    described_class.new(work_item_repo: repo, agent_session: agent_session, event_store: event_store)
  end

  let(:repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:agent_session) { WorkCoordinator::Adapters::FakeAgentSession.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:work_item) { repo.save(build(:work_item_domain, state: :created)) }

  describe "#call" do
    it "returns the work item in the active state" do
      expect(start.call(work_item_id: work_item.id)).to be_active
    end

    it "persists the activated work item" do
      start.call(work_item_id: work_item.id)

      expect(repo.find(work_item.id)).to be_active
    end

    it "advances updated_at" do
      original = work_item.with(updated_at: Time.now - 3600)
      repo.save(original)

      started = start.call(work_item_id: original.id)

      expect(started.updated_at).to be > original.updated_at
    end

    it "leaves created_at alone" do
      started = start.call(work_item_id: work_item.id)

      expect(started.created_at).to eq(work_item.created_at)
    end

    it "opens an agent session for the work item" do
      start.call(work_item_id: work_item.id)

      expect(agent_session.active_session(work_item_id: work_item.id)).not_to be_nil
    end

    it "appends a work_item.started event" do
      start.call(work_item_id: work_item.id)

      expect(event_store.all.last).to have_attributes(
        type: "work_item.started", work_item_id: work_item.id, source: "system", data: {}
      )
    end

    it "raises when the work item is unknown" do
      expect { start.call(work_item_id: "missing") }
        .to raise_error(RuntimeError, "work item not found: missing")
    end

    it "records nothing when the work item is unknown" do
      expect { start.call(work_item_id: "missing") }.to raise_error(RuntimeError)

      expect(event_store.all).to be_empty
    end

    it "starts an already-active item again, opening a fresh session" do
      first = start.call(work_item_id: work_item.id)
      first_session = agent_session.active_session(work_item_id: work_item.id)

      start.call(work_item_id: first.id)

      expect(agent_session.active_session(work_item_id: work_item.id)).not_to eq(first_session)
    end
  end
end
