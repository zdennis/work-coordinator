# frozen_string_literal: true

require "work_coordinator/adapters/tmux_agent_session"
require "work_coordinator/adapters/in_memory_work_item_repository"

RSpec.describe WorkCoordinator::Adapters::TmuxAgentSession do
  subject(:session) { described_class.new(work_item_repo: repo) }

  let(:repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }

  def success_status
    instance_double(Process::Status, success?: true)
  end

  def failure_status
    instance_double(Process::Status, success?: false)
  end

  describe "#deliver_to_pane" do
    context "when the pane exists" do
      before do
        call_count = 0
        allow(Open3).to receive(:capture2e) do |*cmd|
          call_count += 1
          if cmd.include?("list-panes")
            ["0\n1\n", success_status]
          else
            ["", success_status]
          end
        end
      end

      it "sends the message to tmux pane 0 (domain pane 1) without raising" do
        expect do
          session.deliver_to_pane(workspace_name: "growth-engine", pane_index: 1, message: "do the thing")
        end.not_to raise_error
      end

      it "converts domain pane index 1 to tmux pane index 0 in the send-keys target" do
        captured_cmds = []
        allow(Open3).to receive(:capture2e) do |*cmd|
          captured_cmds << cmd
          if cmd.include?("list-panes")
            ["0\n1\n", success_status]
          else
            ["", success_status]
          end
        end

        session.deliver_to_pane(workspace_name: "growth-engine", pane_index: 1, message: "do the thing")

        send_keys_cmd = captured_cmds.find { |c| c.include?("send-keys") }
        expect(send_keys_cmd).to include("growth-engine:0.0")
      end
    end

    context "when the pane does not exist" do
      before do
        allow(Open3).to receive(:capture2e).and_return(["", success_status])
      end

      it "raises PaneNotFoundError" do
        expect do
          session.deliver_to_pane(workspace_name: "growth-engine", pane_index: 1, message: "foo")
        end.to raise_error(WorkCoordinator::Ports::AgentSession::PaneNotFoundError, /pane 1 not found/)
      end
    end

    context "when list-panes reports tmux failure" do
      before do
        allow(Open3).to receive(:capture2e).and_return(["no server", failure_status])
      end

      it "raises PaneNotFoundError (treats missing session as missing pane)" do
        expect do
          session.deliver_to_pane(workspace_name: "missing-session", pane_index: 1, message: "foo")
        end.to raise_error(WorkCoordinator::Ports::AgentSession::PaneNotFoundError)
      end
    end

    context "when send-keys fails" do
      before do
        allow(Open3).to receive(:capture2e) do |*cmd|
          if cmd.include?("list-panes")
            ["0\n", success_status]
          else
            ["bad pane: 0", failure_status]
          end
        end
      end

      it "raises RuntimeError with tmux output" do
        expect do
          session.deliver_to_pane(workspace_name: "growth-engine", pane_index: 1, message: "foo")
        end.to raise_error(RuntimeError, /tmux send-keys failed/)
      end
    end
  end
end
