# frozen_string_literal: true

require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_agent_session"

RSpec.describe WorkCoordinator::Application::RouteMessage do
  subject(:route) do
    described_class.new(work_item_repo: repo, agent_session: agent_session, event_store: event_store)
  end

  let(:repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:agent_session) { WorkCoordinator::Adapters::FakeAgentSession.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:work_item) do
    repo.save(build(:work_item_domain, external_reference: "ABC-123", state: :waiting_for_human))
  end

  def start_session_for(item)
    agent_session.start_session(work_item_id: item.id)
  end

  describe "#call with a live session" do
    before { start_session_for(work_item) }

    it "reports the message as routed" do
      expect(route.call(raw_message: "ABC-123 go ahead")).to have_attributes(routed: true, body: "go ahead")
    end

    it "returns the activated work item" do
      result = route.call(raw_message: "ABC-123 go ahead")

      expect(result.work_item).to have_attributes(id: work_item.id, state: :active)
    end

    it "persists the activation" do
      route.call(raw_message: "ABC-123 go ahead")

      expect(repo.find(work_item.id)).to be_active
    end

    it "delivers the stripped body to the session" do
      route.call(raw_message: "ABC-123 go ahead")

      expect(agent_session.delivered_messages)
        .to eq([{ session_id: agent_session.active_session(work_item_id: work_item.id), message: "go ahead" }])
    end

    it "appends a human.replied event carrying both forms of the message" do
      route.call(raw_message: "ABC-123 go ahead")

      expect(event_store.all.last).to have_attributes(
        type: "human.replied",
        work_item_id: work_item.id,
        source: "human",
        data: { raw_message: "ABC-123 go ahead", body: "go ahead" }
      )
    end

    it "keeps newlines in a multi-line body" do
      result = route.call(raw_message: "ABC-123 first line\nsecond line")

      expect(result.body).to eq("first line\nsecond line")
    end

    it "routes to the work item whose reference matches, not the first one stored" do
      other = repo.save(build(:work_item_domain, external_reference: "ZZZ-999"))
      other_session = start_session_for(other)

      result = route.call(raw_message: "ZZZ-999 over here")

      expect(result.work_item.id).to eq(other.id)
      expect(agent_session.delivered_messages.last[:session_id]).to eq(other_session)
    end
  end

  describe "#call without a routable prefix" do
    before { start_session_for(work_item) }

    it "returns the raw message unrouted when there is no prefix" do
      expect(route.call(raw_message: "just talking"))
        .to have_attributes(routed: false, work_item: nil, body: "just talking")
    end

    it "does not route a lowercase reference" do
      expect(route.call(raw_message: "abc-123 go ahead")).to have_attributes(routed: false, work_item: nil)
    end

    it "does not route a reference that is not followed by a body" do
      expect(route.call(raw_message: "ABC-123")).to have_attributes(routed: false, work_item: nil)
    end

    it "does not route a reference that appears mid-message" do
      expect(route.call(raw_message: "re: ABC-123 go ahead")).to have_attributes(routed: false, work_item: nil)
    end

    it "delivers nothing" do
      route.call(raw_message: "just talking")

      expect(agent_session.delivered_messages).to be_empty
    end

    it "records nothing" do
      route.call(raw_message: "just talking")

      expect(event_store.all).to be_empty
    end
  end

  describe "#call with an unknown reference" do
    it "returns the stripped body with no work item" do
      expect(route.call(raw_message: "XYZ-999 anyone there"))
        .to have_attributes(routed: false, work_item: nil, body: "anyone there")
    end

    it "records nothing" do
      route.call(raw_message: "XYZ-999 anyone there")

      expect(event_store.all).to be_empty
    end
  end

  describe "#call when the work item has no live session" do
    before { work_item }

    it "returns the matched work item but reports it unrouted" do
      result = route.call(raw_message: "ABC-123 go ahead")

      expect(result).to have_attributes(routed: false, body: "go ahead")
      expect(result.work_item.id).to eq(work_item.id)
    end

    it "leaves the work item in its waiting state" do
      route.call(raw_message: "ABC-123 go ahead")

      expect(repo.find(work_item.id)).to be_waiting_for_human
    end

    it "records nothing" do
      route.call(raw_message: "ABC-123 go ahead")

      expect(event_store.all).to be_empty
    end

    it "stops routing once the session ends" do
      session_id = start_session_for(work_item)
      agent_session.end_session(session_id: session_id)

      expect(route.call(raw_message: "ABC-123 go ahead")).to have_attributes(routed: false)
    end
  end

  describe "#call with a reply: prefix" do
    let(:notified_item) do
      repo.save(build(:work_item_domain, external_reference: "MS-123", state: :waiting_for_human))
    end

    before do
      notified_item
      event_store.append(
        type: "system.notified",
        work_item_id: notified_item.id,
        source: "system",
        data: { "ref" => "MS-123", "body" => "CI failed on branch main" }
      )
      start_session_for(notified_item)
    end

    it "reports the message as routed" do
      expect(route.call(raw_message: "reply: investigate")).to have_attributes(routed: true)
    end

    it "returns the activated work item" do
      result = route.call(raw_message: "reply: investigate")

      expect(result.work_item).to have_attributes(id: notified_item.id, state: :active)
    end

    it "delivers the combined instruction and context to the agent session" do
      route.call(raw_message: "reply: investigate, debug, fix")

      expected = "Current instruction: investigate, debug, fix\nContext: [MS-123] CI failed on branch main"
      expect(agent_session.delivered_messages.last[:message]).to eq(expected)
    end

    it "sets body on the result to the combined message" do
      result = route.call(raw_message: "reply: investigate, debug, fix")

      expected = "Current instruction: investigate, debug, fix\nContext: [MS-123] CI failed on branch main"
      expect(result.body).to eq(expected)
    end

    it "appends a human.replied event with the combined body" do
      route.call(raw_message: "reply: investigate")

      expect(event_store.all.last).to have_attributes(
        type: "human.replied",
        work_item_id: notified_item.id,
        source: "human"
      )
    end

    it "handles REPLY: in upper case" do
      expect(route.call(raw_message: "REPLY: investigate")).to have_attributes(routed: true)
    end

    it "strips leading whitespace from the instruction" do
      result = route.call(raw_message: "reply:   lots of spaces")

      expect(result.body).to start_with("Current instruction: lots of spaces")
    end

    it "preserves multi-line instructions" do
      result = route.call(raw_message: "reply: first line\nsecond line")

      expect(result.body).to start_with("Current instruction: first line\nsecond line")
    end

    it "returns unrouted when the work item has no live session" do
      itemless_session = WorkCoordinator::Adapters::FakeAgentSession.new
      router = described_class.new(work_item_repo: repo, agent_session: itemless_session, event_store: event_store)

      expect(router.call(raw_message: "reply: investigate")).to have_attributes(routed: false)
    end
  end

  describe "#call with a reply: and nothing waiting" do
    before { repo.save(build(:work_item_domain, external_reference: "MS-1", state: :active)) }

    it "reports the message unrouted" do
      expect(route.call(raw_message: "reply: go ahead")).to have_attributes(routed: false, work_item: nil)
    end

    it "explains that nothing is waiting" do
      expect(route.call(raw_message: "reply: go ahead"))
        .to have_attributes(reason: :nothing_waiting, human_message: /nothing is waiting/i)
    end

    it "delivers nothing" do
      route.call(raw_message: "reply: go ahead")

      expect(agent_session.delivered_messages).to be_empty
    end
  end

  describe "#call with a bare reply: while several items wait" do
    before do
      %w[MS-1 MS-2].each do |ref|
        item = repo.save(build(:work_item_domain, external_reference: ref, state: :waiting_for_human))
        start_session_for(item)
        event_store.append(type: "system.notified", work_item_id: item.id, source: "system",
                           data: { "ref" => ref, "body" => "needs input" })
      end
    end

    it "refuses to guess" do
      expect(route.call(raw_message: "reply: go ahead"))
        .to have_attributes(routed: false, work_item: nil, reason: :ambiguous_reply)
    end

    it "lists every waiting reference so the human can name one" do
      expect(route.call(raw_message: "reply: go ahead").human_message).to include("MS-1", "MS-2")
    end

    it "delivers nothing" do
      route.call(raw_message: "reply: go ahead")

      expect(agent_session.delivered_messages).to be_empty
    end
  end

  describe "#call with an explicit reference in a reply:" do
    let(:target) do
      repo.save(build(:work_item_domain, external_reference: "MS-42", state: :waiting_for_human))
    end
    let(:other) do
      repo.save(build(:work_item_domain, external_reference: "MS-7", state: :waiting_for_human))
    end

    before do
      start_session_for(target)
      start_session_for(other)
      event_store.append(type: "system.notified", work_item_id: target.id, source: "system",
                         data: { "ref" => "MS-42", "body" => "which database?" })
      event_store.append(type: "system.notified", work_item_id: other.id, source: "system",
                         data: { "ref" => "MS-7", "body" => "unrelated" })
    end

    it "routes to the named item even though others are waiting" do
      expect(route.call(raw_message: "reply: MS-42 use Postgres"))
        .to have_attributes(routed: true, work_item: have_attributes(id: target.id))
    end

    it "drops the reference from the instruction it delivers" do
      route.call(raw_message: "reply: MS-42 use Postgres")

      expect(agent_session.delivered_messages.last[:message])
        .to eq("Current instruction: use Postgres\nContext: [MS-42] which database?")
    end

    it "delivers to the named item's session only" do
      route.call(raw_message: "reply: MS-42 use Postgres")

      expect(agent_session.delivered_messages.map { |m| m[:session_id] })
        .to eq([agent_session.active_session(work_item_id: target.id)])
    end

    it "refuses an unknown reference" do
      expect(route.call(raw_message: "reply: MS-999 hello"))
        .to have_attributes(routed: false, work_item: nil, reason: :unknown_reference)
    end

    it "refuses a finished item, saying so by name" do
      repo.save(build(:work_item_domain, external_reference: "MS-9", state: :completed))

      expect(route.call(raw_message: "reply: MS-9 one more thing"))
        .to have_attributes(routed: false, reason: :not_waiting, human_message: /MS-9 is finished/)
    end

    it "refuses an item that is not waiting for a reply" do
      repo.save(build(:work_item_domain, external_reference: "MS-8", state: :active))

      expect(route.call(raw_message: "reply: MS-8 one more thing"))
        .to have_attributes(routed: false, reason: :not_waiting, human_message: /MS-8 is not waiting/)
    end
  end

  describe "#call when the work item's workspace has a registered agent" do
    subject(:route) do
      described_class.new(work_item_repo: repo, agent_session: agent_session, event_store: event_store,
                          workspace_agent_registry: registry, notify_human: notify_human)
    end

    let(:registry) { WorkCoordinator::Adapters::FakeWorkspaceAgentRegistry.new }
    let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
    let(:notify_human) do
      WorkCoordinator::Application::NotifyHuman.new(message_sender: message_sender, work_item_repo: repo,
                                                    event_store: event_store)
    end
    let(:managed) do
      repo.save(build(:work_item_domain, external_reference: "MS-42", workspace_name: "myapp",
                                         state: :waiting_for_human))
    end

    before do
      start_session_for(managed)
      registry.register(workspace_name: "myapp", socket_path: "/tmp/myapp.sock", pipeline: "build", epoch: "e1")
    end

    it "injects the steer instead of typing into the pane" do
      route.call(raw_message: "MS-42 use Postgres not SQLite")

      expect(agent_session.injections).to eq([{ workspace_name: "myapp", work_item_ref: "MS-42",
                                                body: "use Postgres not SQLite", interrupt: false }])
      expect(agent_session.delivered_messages).to be_empty
    end

    it "reports the message as routed and activates the item" do
      expect(route.call(raw_message: "MS-42 use Postgres"))
        .to have_attributes(routed: true, work_item: have_attributes(state: :active))
    end

    it "falls back to tmux delivery for a workspace with no registration" do
      unmanaged = repo.save(build(:work_item_domain, external_reference: "MS-7", workspace_name: "other"))
      start_session_for(unmanaged)

      route.call(raw_message: "MS-7 carry on")

      expect(agent_session.injections).to be_empty
      expect(agent_session.delivered_messages.last[:message]).to eq("carry on")
    end

    context "when the agent refuses the steer" do
      before { agent_session.inject_reply = { ok: false, error: "no_active_pipeline" } }

      it "reports the message unrouted with the agent's error as the reason" do
        expect(route.call(raw_message: "MS-42 use Postgres"))
          .to have_attributes(routed: false, reason: :inject_failed, work_item: have_attributes(id: managed.id))
      end

      it "tells the human the steer did not land" do
        route.call(raw_message: "MS-42 use Postgres")

        expect(message_sender.sent_messages.last[:body]).to include("MS-42", "no_active_pipeline")
      end

      it "does not activate the item or record a reply" do
        route.call(raw_message: "MS-42 use Postgres")

        expect(repo.find(managed.id)).to be_waiting_for_human
        expect(event_store.all.map(&:type)).not_to include("human.replied")
      end
    end
  end

  describe "waiting-item lookup" do
    it "returns only the items in waiting_for_human" do
      waiting = repo.save(build(:work_item_domain, external_reference: "MS-1", state: :waiting_for_human))
      repo.save(build(:work_item_domain, external_reference: "MS-2", state: :active))

      expect(repo.find_all_waiting_for_human.map(&:id)).to eq([waiting.id])
    end
  end

  describe WorkCoordinator::Application::Result do
    it "compares by value" do
      attrs = { routed: true, work_item: nil, body: "hi" }

      one = described_class.new(**attrs)
      another = described_class.new(**attrs)

      expect(one).to eq(another)
    end
  end
end
