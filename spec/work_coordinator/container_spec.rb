# frozen_string_literal: true

RSpec.describe WorkCoordinator::Container do
  before do
    allow(WorkCoordinator::Persistence).to receive(:connect!)
    allow(WorkCoordinator::Persistence).to receive(:migrate!)
  end

  def receivers_of(container)
    container.message_receiver.instance_variable_get(:@receivers)
  end

  it "defaults to local mode" do
    container = described_class.new

    expect(container.message_receiver).to be_an_instance_of(WorkCoordinator::Adapters::CompositeMessageReceiver)
    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::SocketMessageReceiver)])
  end

  it "wraps a socket receiver for local mode" do
    container = described_class.new(modes: [:local])

    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::SocketMessageReceiver)])
    expect(container.message_sender).to be_an_instance_of(WorkCoordinator::Adapters::SocketMessageSender)
  end

  it "wraps an inbox poller for messages mode" do
    container = described_class.new(modes: [:messages])

    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::MessagesInboxPoller)])
    expect(container.inbound_message_repo)
      .to be_an_instance_of(WorkCoordinator::Adapters::SqliteInboundMessageRepository)
    expect(container.message_sender).to be_an_instance_of(WorkCoordinator::Adapters::AppleScriptMessageSender)
  end

  it "wraps both receivers when both modes are given" do
    container = described_class.new(modes: %i[local messages])

    expect(receivers_of(container)).to match([
                                               an_instance_of(WorkCoordinator::Adapters::SocketMessageReceiver),
                                               an_instance_of(WorkCoordinator::Adapters::MessagesInboxPoller)
                                             ])
  end

  it "deduplicates repeated modes" do
    container = described_class.new(modes: %i[local local])

    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::SocketMessageReceiver)])
  end

  it "accepts string modes" do
    container = described_class.new(modes: ["messages"])

    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::MessagesInboxPoller)])
  end

  it "raises on an unknown mode" do
    expect { described_class.new(modes: [:carrier_pigeon]) }.to raise_error(ArgumentError, /carrier_pigeon/)
  end
end
