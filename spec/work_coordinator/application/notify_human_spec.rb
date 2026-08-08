# frozen_string_literal: true

require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_message_sender"

RSpec.describe WorkCoordinator::Application::NotifyHuman do
  subject(:notify) do
    described_class.new(message_sender: sender, work_item_repo: repo, event_store: event_store)
  end

  let(:sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:work_item) { repo.save(build(:work_item_domain, external_reference: "ABC-123", state: :active)) }

  describe "#call" do
    it "returns the work item parked for the human" do
      expect(notify.call(work_item_id: work_item.id, body: "Which branch?")).to be_waiting_for_human
    end

    it "persists the waiting state" do
      notify.call(work_item_id: work_item.id, body: "Which branch?")

      expect(repo.find(work_item.id)).to be_waiting_for_human
    end

    it "sends the question prefixed with the reference and reply instructions" do
      notify.call(work_item_id: work_item.id, body: "Which branch?")

      expect(sender.sent_messages).to eq(
        [{ to: nil, body: "[ABC-123] Which branch?\nReply: ABC-123 <your response>", conversation_id: nil }]
      )
    end

    it "sends a body the router can round-trip back to the same work item" do
      notify.call(work_item_id: work_item.id, body: "Which branch?")
      sent = sender.sent_messages.first[:body]

      expect(sent).to include("ABC-123 <your response>")
    end

    it "appends an agent.question_asked event with the unformatted body" do
      notify.call(work_item_id: work_item.id, body: "Which branch?")

      expect(event_store.all.find { |e| e.type == "agent.question_asked" }).to have_attributes(
        type: "agent.question_asked",
        work_item_id: work_item.id,
        source: "agent",
        data: { body: "Which branch?" }
      )
    end

    it "appends a system.notified event with the ref and unformatted body" do
      notify.call(work_item_id: work_item.id, body: "Which branch?")

      expect(event_store.all.find { |e| e.type == "system.notified" }).to have_attributes(
        type: "system.notified",
        work_item_id: work_item.id,
        source: "system",
        data: { ref: "ABC-123", body: "Which branch?" }
      )
    end

    it "records system.notified after agent.question_asked" do
      notify.call(work_item_id: work_item.id, body: "Which branch?")

      types = event_store.all.map(&:type)
      expect(types.index("agent.question_asked")).to be < types.index("system.notified")
    end

    it "does not append system.notified when the work item is unknown" do
      expect { notify.call(work_item_id: "missing", body: "hi") }.to raise_error(RuntimeError)

      expect(event_store.all.select { |e| e.type == "system.notified" }).to be_empty
    end

    it "advances updated_at" do
      original = repo.save(work_item.with(updated_at: Time.now - 3600))

      waiting = notify.call(work_item_id: original.id, body: "Which branch?")

      expect(waiting.updated_at).to be > original.updated_at
    end

    it "raises when the work item is unknown" do
      expect { notify.call(work_item_id: "missing", body: "Which branch?") }
        .to raise_error(RuntimeError, "work item not found: missing")
    end

    it "sends nothing when the work item is unknown" do
      expect { notify.call(work_item_id: "missing", body: "hi") }.to raise_error(RuntimeError)

      expect(sender.sent_messages).to be_empty
    end

    it "still sends when the work item has no external reference, prefixing an empty one" do
      unreferenced = repo.save(build(:work_item_domain, external_reference: nil))

      notify.call(work_item_id: unreferenced.id, body: "Which branch?")

      expect(sender.sent_messages.first[:body]).to eq("[] Which branch?\nReply:  <your response>")
    end
  end
end
