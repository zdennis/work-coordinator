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

    it "resolves the alias to the full session name before delivery" do
      use_case.call(workspace_name: "WC", instructions: "echo hi", recipient: nil)
      expect(agent_session.delivered_messages).to contain_exactly(
        hash_including(session_id: "work-coordinator", message: "echo hi")
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

  context "when delivery succeeds" do
    it "returns a successful Result" do
      expect(call).to have_attributes(success: true, error: nil)
    end

    it "delivers the instructions to the workspace via the agent session" do
      call
      expect(agent_session.delivered_messages).to contain_exactly(
        hash_including(session_id: "my-service", message: "add validation")
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
      expect(agent_session.delivered_messages.first[:message]).to eq("step one\nstep two")
    end
  end

  context "when the agent session raises" do
    let(:agent_session) do
      Class.new do
        def deliver(**) = raise StandardError, "agent unavailable"

        def method_missing(*) = nil

        def respond_to_missing?(*) = true
      end.new
    end

    it "returns a failed Result" do
      result = call
      expect(result).to have_attributes(success: false)
      expect(result.error).to eq("agent unavailable")
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

    it "appends the context to the instructions with a blank line separator" do
      use_case.call(workspace_name: "my-service", instructions: "research foo", recipient: nil)
      expect(agent_session.delivered_messages.first[:message]).to eq(
        "research foo\n\nHow to work:\n\n$rpi"
      )
    end

    it "uses only the original instructions for the acknowledgment summary" do
      use_case.call(workspace_name: "my-service", instructions: "research foo", recipient: nil)
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to my-service: research foo")
    end
  end

  context "when instructions start with a slash command" do
    it "normalizes a space after the command to two newlines" do
      use_case.call(workspace_name: "my-service", instructions: "/clear How to work:\n\n$rpi", recipient: nil)
      expect(agent_session.delivered_messages.first[:message]).to eq("/clear\n\nHow to work:\n\n$rpi")
    end

    it "normalizes a single newline after the command to two newlines" do
      use_case.call(workspace_name: "my-service", instructions: "/clear\nHow to work:\n\n$rpi", recipient: nil)
      expect(agent_session.delivered_messages.first[:message]).to eq("/clear\n\nHow to work:\n\n$rpi")
    end

    it "leaves an already-correct double-newline separator unchanged" do
      use_case.call(workspace_name: "my-service", instructions: "/clear\n\nHow to work:\n\n$rpi", recipient: nil)
      expect(agent_session.delivered_messages.first[:message]).to eq("/clear\n\nHow to work:\n\n$rpi")
    end

    it "leaves a bare slash command unchanged" do
      use_case.call(workspace_name: "my-service", instructions: "/clear", recipient: nil)
      expect(agent_session.delivered_messages.first[:message]).to eq("/clear")
    end
  end

  context "when instruction_context is empty" do
    it "delivers instructions unchanged" do
      use_case.call(workspace_name: "my-service", instructions: "research foo", recipient: nil)
      expect(agent_session.delivered_messages.first[:message]).to eq("research foo")
    end
  end

  context "when workspace_name is empty" do
    it "still sends to whatever workspace was given" do
      call(workspace_name: "", instructions: "add validation")
      expect(message_sender.sent_messages.first[:body]).to eq("Sent to : add validation")
    end
  end
end
