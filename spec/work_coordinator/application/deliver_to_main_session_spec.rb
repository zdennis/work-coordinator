# frozen_string_literal: true

require "work_coordinator/application/deliver_to_main_session"
require "work_coordinator/adapters/fake_agent_session"
require "work_coordinator/adapters/fake_message_sender"

RSpec.describe WorkCoordinator::Application::DeliverToMainSession do
  subject(:use_case) do
    described_class.new(agent_session: agent_session, message_sender: message_sender)
  end

  let(:agent_session)  { WorkCoordinator::Adapters::FakeAgentSession.new }
  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }

  def call(workspace_name: "growth-engine", instructions: "add validation", recipient: nil)
    use_case.call(workspace_name: workspace_name, instructions: instructions, recipient: recipient)
  end

  context "when the pane exists" do
    before { agent_session.stub_pane(workspace_name: "growth-engine", pane_index: 1) }

    it "returns a successful Result" do
      expect(call).to have_attributes(success: true, error: nil)
    end

    it "delivers the instructions to domain pane 1 of the workspace" do
      call
      expect(agent_session.delivered_to_pane).to contain_exactly(
        hash_including(workspace_name: "growth-engine", pane_index: 1, message: "add validation")
      )
    end

    it "sends an acknowledgment to the recipient" do
      call(recipient: "+15551234567")
      expect(message_sender.sent_messages).to contain_exactly(
        hash_including(to: "+15551234567", body: "Sent to growth-engine")
      )
    end

    it "sends acknowledgment with nil recipient when no recipient given" do
      call(recipient: nil)
      expect(message_sender.sent_messages.first).to include(to: nil, body: "Sent to growth-engine")
    end

    it "preserves multiline instructions" do
      call(instructions: "step one\nstep two")
      expect(agent_session.delivered_to_pane.first[:message]).to eq("step one\nstep two")
    end
  end

  context "when the pane does not exist" do
    it "returns a failed Result" do
      result = call
      expect(result).to have_attributes(success: false)
      expect(result.error).to include("pane 1 not stubbed")
    end

    it "sends the error message to the recipient" do
      call(recipient: "+15551234567")
      sent = message_sender.sent_messages.first
      expect(sent[:to]).to eq("+15551234567")
      expect(sent[:body]).to start_with("Error:")
    end

    it "does not raise" do
      expect { call }.not_to raise_error
    end
  end

  context "when workspace_name is empty" do
    before { agent_session.stub_pane(workspace_name: "", pane_index: 1) }

    it "still sends to whatever workspace was given" do
      call(workspace_name: "")
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to ")
    end
  end
end
