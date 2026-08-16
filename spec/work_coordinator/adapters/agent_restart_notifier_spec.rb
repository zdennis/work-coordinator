# frozen_string_literal: true

require "spec_helper"
require "support/fake_workspace_agent"
require "tmpdir"

RSpec.describe WorkCoordinator::Adapters::AgentRestartNotifier do
  subject(:notifier) { described_class.new(registry: registry) }

  let(:registry) { WorkCoordinator::Adapters::FakeWorkspaceAgentRegistry.new }
  let(:tmpdir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmpdir) }

  def register!(name)
    path = File.join(tmpdir, "#{name}.sock")
    registry.register(workspace_name: name, socket_path: path, pipeline: "build", epoch: "e1")
    path
  end

  context "when agents are registered and listening" do
    let(:myapp_path) { register!("myapp") }
    let(:other_path) { register!("other") }
    let(:myapp) { FakeWorkspaceAgent.new(socket_path: myapp_path) }
    let(:other) { FakeWorkspaceAgent.new(socket_path: other_path) }

    before do
      myapp.start
      other.start
    end

    after do
      myapp.stop
      other.stop
    end

    it "sends a coordinator_restart message to each agent" do
      notifier.notify_all
      myapp.wait_for_message
      other.wait_for_message

      [myapp, other].each do |agent|
        received = agent.received_messages.first
        expect(received).to include("type" => "coordinator_restart")
        expect(received["dispatch_id"]).to match(/\Ad-[0-9a-f]{16}\z/)
      end
    end
  end

  context "when a socket file is missing" do
    let(:reachable_path) { register!("reachable") }
    let(:agent) { FakeWorkspaceAgent.new(socket_path: reachable_path) }

    before do
      registry.register(
        workspace_name: "gone",
        socket_path: File.join(tmpdir, "gone.sock"),
        pipeline: "build",
        epoch: "e1"
      )
      agent.start
    end

    after { agent.stop }

    it "skips the unreachable agent and still notifies the rest" do
      expect { notifier.notify_all }.not_to raise_error
      agent.wait_for_message

      expect(agent.received_messages.first).to include("type" => "coordinator_restart")
    end
  end

  context "when a socket exists but nothing is listening" do
    it "does not raise" do
      path = File.join(tmpdir, "stale.sock")
      UNIXServer.new(path).close
      registry.register(workspace_name: "stale", socket_path: path, pipeline: "build", epoch: "e1")

      expect { notifier.notify_all }.not_to raise_error
    end
  end

  context "when no agents are registered" do
    it "does nothing" do
      expect { notifier.notify_all }.not_to raise_error
    end
  end
end
