# frozen_string_literal: true

require "work_coordinator/application/deliver_to_main_session"
require "work_coordinator/adapters/fake_agent_session"
require "work_coordinator/adapters/fake_message_sender"

RSpec.describe WorkCoordinator::Application::DeliverToMainSession do
  subject(:use_case) do
    described_class.new(agent_session: agent_session, message_sender: message_sender)
  end

  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:agent_session)  { WorkCoordinator::Adapters::FakeAgentSession.new }

  context "when aliases are configured" do
    subject(:use_case) do
      described_class.new(
        agent_session: agent_session,
        message_sender: message_sender,
        aliases: { "WC" => "work-coordinator" }
      )
    end

    before { agent_session.stub_pane(workspace_name: "work-coordinator", pane_index: 2) }

    it "resolves the alias to the full session name before delivery" do
      use_case.call(workspace_name: "WC", instructions: "echo hi", recipient: nil)
      expect(agent_session.delivered_to_pane).to contain_exactly(
        hash_including(workspace_name: "work-coordinator", pane_index: 2, message: "echo hi")
      )
    end

    it "sends acknowledgment using the resolved session name with instructions" do
      use_case.call(workspace_name: "WC", instructions: "echo hi", recipient: nil)
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to work-coordinator: echo hi")
    end
  end

  def call(workspace_name: "my-service", instructions: "add validation", recipient: nil)
    use_case.call(workspace_name: workspace_name, instructions: instructions, recipient: recipient)
  end

  context "when the pane exists" do
    before { agent_session.stub_pane(workspace_name: "my-service", pane_index: 2) }

    it "returns a successful Result" do
      expect(call).to have_attributes(success: true, error: nil)
    end

    it "delivers the instructions to domain pane 2 of the workspace" do
      call
      expect(agent_session.delivered_to_pane).to contain_exactly(
        hash_including(workspace_name: "my-service", pane_index: 2, message: "add validation")
      )
    end

    it "sends an acknowledgment to the recipient with instructions summary" do
      call(recipient: "+15551234567")
      expect(message_sender.sent_messages).to contain_exactly(
        hash_including(to: "+15551234567", body: "Sent to my-service: add validation")
      )
    end

    it "sends acknowledgment with nil recipient when no recipient given" do
      call(recipient: nil)
      expect(message_sender.sent_messages.first).to include(to: nil, body: "Sent to my-service: add validation")
    end

    it "truncates long instructions to 80 chars in the acknowledgment" do
      long = "a" * 100
      call(instructions: long)
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to my-service: #{'a' * 80}...")
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
      expect(result.error).to include("pane 2 not stubbed")
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

  context "when instruction_context is configured" do
    subject(:use_case) do
      described_class.new(
        agent_session: agent_session,
        message_sender: message_sender,
        instruction_context: "How to work:\n\n$rpi"
      )
    end

    before { agent_session.stub_pane(workspace_name: "my-service", pane_index: 2) }

    it "appends the context to the instructions with a blank line separator" do
      use_case.call(workspace_name: "my-service", instructions: "research foo", recipient: nil)
      expect(agent_session.delivered_to_pane.first[:message]).to eq(
        "research foo\n\nHow to work:\n\n$rpi"
      )
    end

    it "uses only the original instructions for the acknowledgment summary" do
      use_case.call(workspace_name: "my-service", instructions: "research foo", recipient: nil)
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to my-service: research foo")
    end
  end

  context "when instruction_context is empty" do
    before { agent_session.stub_pane(workspace_name: "my-service", pane_index: 2) }

    it "delivers instructions unchanged" do
      use_case.call(workspace_name: "my-service", instructions: "research foo", recipient: nil)
      expect(agent_session.delivered_to_pane.first[:message]).to eq("research foo")
    end
  end

  context "when workspace_name is empty" do
    before { agent_session.stub_pane(workspace_name: "", pane_index: 2) }

    it "still sends to whatever workspace was given" do
      call(workspace_name: "", instructions: "add validation")
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to : add validation")
    end
  end
end
