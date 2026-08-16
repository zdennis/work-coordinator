# frozen_string_literal: true

require "spec_helper"
require "work_coordinator/adapters/fake_agent_session"

# A slash command must have an identity before it is forwarded, so everything
# downstream (status, phase updates, notifications) has something to refer to.
RSpec.describe "slash command work item registration" do
  subject(:receiver) do
    WorkCoordinator::Adapters::AiCommandReceiver.new(
      inner: inner,
      ai_command_handler: ->(msg) { msg },
      deliver_to_main_session: deliver_to_main_session,
      register_command_work_item: register_command_work_item,
      restart_coordinator: -> {},
      update_and_restart: -> {}
    )
  end

  let(:work_item_repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:message_sender) { WorkCoordinator::Adapters::FakeMessageSender.new }

  let(:agent_session) do
    WorkCoordinator::Adapters::FakeAgentSession.new.tap do |session|
      session.stub_pane(
        workspace_name: "myapp",
        pane_index: WorkCoordinator::Application::DeliverToMainSession::MAIN_PANE_INDEX
      )
    end
  end

  let(:register_command_work_item) do
    WorkCoordinator::Application::RegisterCommandWorkItem.new(
      register_work_item: WorkCoordinator::Application::RegisterWorkItem.new(
        work_item_repo: work_item_repo, event_store: event_store
      ),
      work_item_repo: work_item_repo
    )
  end

  let(:deliver_to_main_session) do
    WorkCoordinator::Application::DeliverToMainSession.new(
      agent_session: agent_session,
      message_sender: message_sender
    )
  end

  let(:inner) do
    Class.new do
      include WorkCoordinator::Ports::MessageReceiver

      def initialize(messages) = @messages = messages
      def start(&block) = @messages.each { |msg| block.call(msg) }
      def stop = nil
    end.new(messages)
  end

  # MessagesInboxPoller splits "ai: /build myapp add OAuth" into
  # work_item_ref: "/build", body: "myapp add OAuth".
  let(:messages) { [{ work_item_ref: "/build", body: "myapp add OAuth", received_at: Time.now }] }

  it "creates a work item for the command" do
    receiver.start { |m| m }

    expect(work_item_repo.find_all.size).to eq(1)
  end

  it "records the workspace named in the command" do
    receiver.start { |m| m }

    expect(work_item_repo.find_all.first).to have_attributes(
      workspace_name: "myapp",
      external_reference: "WC-1",
      state: :created
    )
  end

  it "creates the work item before the command reaches the pane" do
    items_at_delivery = nil
    allow(agent_session).to receive(:deliver_to_pane).and_wrap_original do |original, **kwargs|
      items_at_delivery = work_item_repo.find_all.size
      original.call(**kwargs)
    end

    receiver.start { |m| m }

    expect(items_at_delivery).to eq(1)
  end

  it "names the work item reference in the acknowledgement to the human" do
    receiver.start { |m| m }

    expect(message_sender.sent_messages.last[:body]).to start_with("[WC-1] ")
  end

  it "allocates a fresh reference per command" do
    messages << { work_item_ref: "/test", body: "myapp", received_at: Time.now }

    receiver.start { |m| m }

    expect(work_item_repo.find_all.map(&:external_reference)).to contain_exactly("WC-1", "WC-2")
  end
end
