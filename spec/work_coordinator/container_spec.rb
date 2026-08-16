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

  it "wraps an inbox poller in an AiCommandReceiver for messages mode" do
    container = described_class.new(modes: [:messages])

    outer = receivers_of(container)
    expect(outer).to match([an_instance_of(WorkCoordinator::Adapters::AiCommandReceiver)])
    expect(outer.first.instance_variable_get(:@inner))
      .to be_an_instance_of(WorkCoordinator::Adapters::MessagesInboxPoller)
    expect(container.inbound_message_repo)
      .to be_an_instance_of(WorkCoordinator::Adapters::SqliteInboundMessageRepository)
    expect(container.message_sender).to be_an_instance_of(WorkCoordinator::Adapters::AppleScriptMessageSender)
    expect(container.deliver_to_main_session)
      .to be_an_instance_of(WorkCoordinator::Application::DeliverToMainSession)
  end

  it "wraps both receivers when both modes are given" do
    container = described_class.new(modes: %i[local messages])

    expect(receivers_of(container)).to match([
                                               an_instance_of(WorkCoordinator::Adapters::SocketMessageReceiver),
                                               an_instance_of(WorkCoordinator::Adapters::AiCommandReceiver)
                                             ])
  end

  it "deduplicates repeated modes" do
    container = described_class.new(modes: %i[local local])

    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::SocketMessageReceiver)])
  end

  it "accepts string modes" do
    container = described_class.new(modes: ["messages"])

    expect(receivers_of(container)).to match([an_instance_of(WorkCoordinator::Adapters::AiCommandReceiver)])
  end

  it "raises on an unknown mode" do
    expect { described_class.new(modes: [:carrier_pigeon]) }.to raise_error(ArgumentError, /carrier_pigeon/)
  end

  it "exposes the config's role when no role is given" do
    container = described_class.new

    expect(container.config.role).to eq(WorkCoordinator::Config.load.role)
  end

  it "overrides the config's role when one is given" do
    config = WorkCoordinator::Config.new("/nonexistent/config.yml")
    container = described_class.new(config: config, role: "home")

    expect(container.config.role).to eq("home")
    expect(config.role).to eq("default")
  end

  it "wires the restart collaborators" do
    container = described_class.new

    expect(container.restart_state_repo).to be_a(WorkCoordinator::Adapters::SqliteRestartStateRepository)
    expect(container.git_runner).to be_a(WorkCoordinator::Adapters::ShellGitRunner)
    expect(container.restart_coordinator).to be_a(WorkCoordinator::Application::RestartCoordinator)
    expect(container.update_and_restart).to be_a(WorkCoordinator::Application::UpdateAndRestart)
  end

  it "passes argv and env through to the restart coordinator" do
    container = described_class.new(argv: ["bin/work-coordinator", "run"], env: { "WC_TEST" => "1" })
    coordinator = container.restart_coordinator

    expect(coordinator.instance_variable_get(:@argv)).to eq(["bin/work-coordinator", "run"])
    expect(coordinator.instance_variable_get(:@env)).to eq({ "WC_TEST" => "1" })
  end
end
