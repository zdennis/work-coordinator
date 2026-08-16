# frozen_string_literal: true

require "spec_helper"

RSpec.shared_examples "a workspace agent registry" do
  describe "#register" do
    it "stores the registration" do
      expect(registry.register(workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false,
                               epoch: "e1")).to eq({ ok: true })

      expect(registry.find("ws-1")).to eq(
        { socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1" }
      )
    end

    it "updates the socket path when the same epoch re-registers" do
      registry.register(workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1")

      expect(registry.register(workspace_name: "ws-1", socket_path: "/tmp/b.sock", pipeline: true,
                               epoch: "e1")).to eq({ ok: true })

      expect(registry.find("ws-1")).to eq(
        { socket_path: "/tmp/b.sock", pipeline: true, epoch: "e1" }
      )
    end

    it "rejects a different epoch for an already registered workspace" do
      registry.register(workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1")

      expect(registry.register(workspace_name: "ws-1", socket_path: "/tmp/b.sock", pipeline: false,
                               epoch: "e2")).to eq({ ok: false, error: "already_registered" })

      expect(registry.find("ws-1")).to eq(
        { socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1" }
      )
    end
  end

  describe "#unregister" do
    it "removes the registration" do
      registry.register(workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1")

      expect(registry.unregister(workspace_name: "ws-1")).to eq({ ok: true })
      expect(registry.find("ws-1")).to be_nil
    end

    it "is a no-op for an unknown workspace" do
      expect(registry.unregister(workspace_name: "nope")).to eq({ ok: true })
    end
  end

  describe "#find" do
    it "returns nil for an unknown workspace" do
      expect(registry.find("nope")).to be_nil
    end
  end

  describe "#registered?" do
    it "is true once registered and false afterwards" do
      expect(registry.registered?("ws-1")).to be(false)

      registry.register(workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1")
      expect(registry.registered?("ws-1")).to be(true)

      registry.unregister(workspace_name: "ws-1")
      expect(registry.registered?("ws-1")).to be(false)
    end
  end

  describe "#all" do
    it "returns every registration" do
      registry.register(workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1")
      registry.register(workspace_name: "ws-2", socket_path: "/tmp/b.sock", pipeline: true, epoch: "e2")

      expect(registry.all).to contain_exactly(
        { workspace_name: "ws-1", socket_path: "/tmp/a.sock", pipeline: false, epoch: "e1" },
        { workspace_name: "ws-2", socket_path: "/tmp/b.sock", pipeline: true, epoch: "e2" }
      )
    end

    it "is empty when nothing is registered" do
      expect(registry.all).to eq([])
    end
  end
end

RSpec.describe WorkCoordinator::Adapters::SqliteWorkspaceAgentRegistry do
  subject(:registry) { described_class.new }

  it_behaves_like "a workspace agent registry"

  # The fake stands in for this adapter everywhere else, so it has to honour
  # the same contract.
  describe WorkCoordinator::Adapters::FakeWorkspaceAgentRegistry do
    subject(:registry) { described_class.new }

    it_behaves_like "a workspace agent registry"
  end
end
