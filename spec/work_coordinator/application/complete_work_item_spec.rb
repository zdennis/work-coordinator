# frozen_string_literal: true

require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_message_sender"

RSpec.describe WorkCoordinator::Application::CompleteWorkItem do
  subject(:complete) do
    described_class.new(message_sender: sender, work_item_repo: repo, event_store: event_store)
  end

  let(:sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:work_item) { repo.save(build(:work_item_domain, external_reference: "WC-42", state: :active)) }

  describe "#call" do
    it "returns the completed work item" do
      expect(complete.call(work_item_id: work_item.id, summary: "Shipped it")).to be_completed
    end

    it "persists the completed state" do
      complete.call(work_item_id: work_item.id, summary: "Shipped it")

      expect(repo.find(work_item.id)).to be_completed
    end

    it "sends a done message without a reply prompt" do
      complete.call(work_item_id: work_item.id, summary: "Shipped it")

      expect(sender.sent_messages).to eq(
        [{ to: nil, body: "[WC-42] Done — Shipped it", conversation_id: nil }]
      )
    end

    it "appends an agent.work_completed event" do
      complete.call(work_item_id: work_item.id, summary: "Shipped it")

      expect(event_store.all.find { |e| e.type == "agent.work_completed" }).to have_attributes(
        work_item_id: work_item.id,
        source: "agent",
        data: { summary: "Shipped it" }
      )
    end

    it "advances updated_at" do
      original = repo.save(work_item.with(updated_at: Time.now - 3600))

      expect(complete.call(work_item_id: original.id, summary: "Shipped it").updated_at)
        .to be > original.updated_at
    end

    context "when the work item is already terminal" do
      before { complete.call(work_item_id: work_item.id, summary: "Shipped it") }

      it "returns the work item unchanged" do
        expect(complete.call(work_item_id: work_item.id, summary: "Shipped it")).to be_completed
      end

      it "does not notify a second time" do
        complete.call(work_item_id: work_item.id, summary: "Shipped it")

        expect(sender.sent_messages.size).to eq(1)
      end

      it "does not append a second event" do
        complete.call(work_item_id: work_item.id, summary: "Shipped it")

        expect(event_store.all.count { |e| e.type == "agent.work_completed" }).to eq(1)
      end
    end

    it "raises when the work item is unknown" do
      expect { complete.call(work_item_id: "missing", summary: "Shipped it") }
        .to raise_error(RuntimeError, "work item not found: missing")
    end

    it "sends nothing when the work item is unknown" do
      expect { complete.call(work_item_id: "missing", summary: "x") }.to raise_error(RuntimeError)

      expect(sender.sent_messages).to be_empty
    end
  end
end
