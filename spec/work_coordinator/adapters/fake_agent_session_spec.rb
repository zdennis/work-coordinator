# frozen_string_literal: true

require "work_coordinator/adapters/fake_agent_session"

RSpec.describe WorkCoordinator::Adapters::FakeAgentSession do
  subject(:session) { described_class.new }

  describe "#deliver_to_pane" do
    context "when the pane has been stubbed" do
      before { session.stub_pane(workspace_name: "ge", pane_index: 1) }

      it "records the delivery" do
        session.deliver_to_pane(workspace_name: "ge", pane_index: 1, message: "hello")
        expect(session.delivered_to_pane).to contain_exactly(
          { workspace_name: "ge", pane_index: 1, message: "hello" }
        )
      end

      it "returns dup on each call so mutations do not affect internal state" do
        session.deliver_to_pane(workspace_name: "ge", pane_index: 1, message: "hello")
        first = session.delivered_to_pane
        first << :extra
        expect(session.delivered_to_pane.length).to eq(1)
      end
    end

    context "when the pane has not been stubbed" do
      it "raises PaneNotFoundError" do
        expect do
          session.deliver_to_pane(workspace_name: "ge", pane_index: 1, message: "hello")
        end.to raise_error(WorkCoordinator::Ports::AgentSession::PaneNotFoundError, /pane 1 not stubbed/)
      end
    end

    it "accumulates multiple deliveries in order" do
      session.stub_pane(workspace_name: "ge", pane_index: 1)
      session.deliver_to_pane(workspace_name: "ge", pane_index: 1, message: "first")
      session.deliver_to_pane(workspace_name: "ge", pane_index: 1, message: "second")
      expect(session.delivered_to_pane.map { |d| d[:message] }).to eq(%w[first second])
    end
  end

  describe "#stub_pane" do
    it "allows multiple distinct panes to be stubbed" do
      session.stub_pane(workspace_name: "ge", pane_index: 1)
      session.stub_pane(workspace_name: "ge", pane_index: 2)
      expect do
        session.deliver_to_pane(workspace_name: "ge", pane_index: 2, message: "hi")
      end.not_to raise_error
    end
  end
end
