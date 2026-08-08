# frozen_string_literal: true

RSpec.describe WorkCoordinator::Domain::Conversation do
  describe "construction" do
    it "exposes the attributes it was built with" do
      inbound = Time.now - 60
      outbound = Time.now
      conversation = build(:conversation_domain, id: "c-1", work_item_id: "wi-1",
                                                 message_thread_id: "thread-9", agent_session: "session-1",
                                                 last_inbound_at: inbound, last_outbound_at: outbound)

      expect(conversation).to have_attributes(
        id: "c-1", work_item_id: "wi-1", message_thread_id: "thread-9",
        agent_session: "session-1", last_inbound_at: inbound, last_outbound_at: outbound
      )
    end

    it "allows a conversation with no thread, session, or traffic yet" do
      conversation = build(:conversation_domain)

      expect(conversation).to have_attributes(
        message_thread_id: nil, agent_session: nil, last_inbound_at: nil, last_outbound_at: nil
      )
    end

    it "requires every member" do
      expect { described_class.new(id: "c-1", work_item_id: "wi-1") }.to raise_error(ArgumentError)
    end

    it "compares by value" do
      attrs = attributes_for(:conversation_domain)

      one = described_class.new(**attrs)
      another = described_class.new(**attrs)

      expect(one).to eq(another)
    end
  end

  describe "#with" do
    it "records inbound traffic without mutating the original" do
      conversation = build(:conversation_domain)
      received_at = Time.now

      updated = conversation.with(last_inbound_at: received_at)

      expect(updated.last_inbound_at).to eq(received_at)
      expect(conversation.last_inbound_at).to be_nil
    end

    it "attaches an agent session to an existing conversation" do
      conversation = build(:conversation_domain, agent_session: nil)

      expect(conversation.with(agent_session: "session-2").agent_session).to eq("session-2")
    end
  end
end
