# frozen_string_literal: true

require "spec_helper"
require "support/fake_workspace_agent"
require "work_coordinator/adapters/fake_agent_session"
require "tmpdir"

RSpec.describe WorkCoordinator::Adapters::WorkspaceAgentSession do
  subject(:session) { described_class.new(tmux: tmux, registry: registry, sleeper: sleeper) }

  let(:slept) { [] }
  let(:sleeper) { ->(seconds) { slept << seconds } }
  let(:tmux) { WorkCoordinator::Adapters::FakeAgentSession.new }
  let(:registry) { WorkCoordinator::Adapters::FakeWorkspaceAgentRegistry.new }
  let(:tmpdir) { Dir.mktmpdir }
  let(:socket_path) { File.join(tmpdir, "agent.sock") }

  after { FileUtils.remove_entry(tmpdir) }

  def register!
    registry.register(workspace_name: "myapp", socket_path: socket_path, pipeline: "build", epoch: "e1")
  end

  describe "#deliver" do
    context "when the workspace has no registered agent" do
      it "falls back to tmux delivery" do
        session.deliver(session_id: "myapp", message: "hello", work_item_ref: "WC-42")

        expect(tmux.delivered_messages).to eq([{ session_id: "myapp", message: "hello" }])
      end
    end

    context "when no work_item_ref is given" do
      it "falls back to tmux delivery even for a registered workspace" do
        register!

        session.deliver(session_id: "myapp", message: "hello")

        expect(tmux.delivered_messages).to eq([{ session_id: "myapp", message: "hello" }])
      end
    end

    context "when the agent is listening" do
      let(:agent) { FakeWorkspaceAgent.new(socket_path: socket_path) }

      before do
        register!
        agent.start
      end

      after { agent.stop }

      it "writes a JSON command to the agent socket instead of tmux" do
        session.deliver(session_id: "myapp", message: "/build add OAuth", work_item_ref: "WC-42")
        agent.wait_for_message

        received = agent.received_messages.first
        expect(received).to include(
          "type" => "command",
          "workspace" => "myapp",
          "work_item_ref" => "WC-42",
          "body" => "/build add OAuth"
        )
        expect(received["dispatch_id"]).to match(/\Ad-[0-9a-f]{16}\z/)
        expect(tmux.delivered_messages).to be_empty
      end
    end

    context "when the socket file is gone" do
      before { register! }

      it "drops the registry entry and falls back to tmux" do
        session.deliver(session_id: "myapp", message: "hello", work_item_ref: "WC-42")

        expect(registry.find("myapp")).to be_nil
        expect(tmux.delivered_messages).to eq([{ session_id: "myapp", message: "hello" }])
      end
    end

    context "when the socket keeps refusing connections" do
      before do
        register!
        FileUtils.touch(socket_path)
        allow(UNIXSocket).to receive(:new).and_raise(Errno::ECONNREFUSED)
      end

      it "raises DeliveryTimeout without falling back to tmux" do
        expect { session.deliver(session_id: "myapp", message: "hello", work_item_ref: "WC-42") }
          .to raise_error(described_class::DeliveryTimeout, /myapp/)

        expect(tmux.delivered_messages).to be_empty
      end

      it "backs off exponentially between attempts" do
        expect { session.deliver(session_id: "myapp", message: "hello", work_item_ref: "WC-42") }
          .to raise_error(described_class::DeliveryTimeout)

        expect(slept).to eq([1, 2, 4, 8, 16, 32])
      end
    end
  end

  describe "delegation" do
    it "delegates start_session, active_session and end_session to tmux" do
      id = session.start_session(work_item_id: "wi-1")

      expect(session.active_session(work_item_id: "wi-1")).to eq(id)

      session.end_session(session_id: id)
      expect(session.active_session(work_item_id: "wi-1")).to be_nil
    end

    it "delegates list_all_panes to tmux" do
      tmux.stub_panes(["a:0.0"])

      expect(session.list_all_panes).to eq(["a:0.0"])
    end

    it "delegates deliver_to_pane to tmux" do
      tmux.stub_pane(workspace_name: "myapp", pane_index: 1)

      session.deliver_to_pane(workspace_name: "myapp", pane_index: 1, message: "hi")

      expect(tmux.delivered_to_pane).to eq([{ workspace_name: "myapp", pane_index: 1, message: "hi" }])
    end
  end
end
