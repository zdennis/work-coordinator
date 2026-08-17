# frozen_string_literal: true

require "json"
require "socket"
require "tmpdir"
require "work_coordinator/application/dispatch_to_agent"
require "work_coordinator/adapters/fake_workspace_agent_registry"

RSpec.describe WorkCoordinator::Application::DispatchToAgent do
  subject(:use_case) do
    described_class.new(registry: registry)
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:registry) { WorkCoordinator::Adapters::FakeWorkspaceAgentRegistry.new }
  let(:socket_path) { File.join(tmpdir, "agent.sock") }
  let(:server) { UNIXServer.new(socket_path) }
  let(:received_payloads) { [] }

  before { server }

  after do
    begin
      server.close
    rescue StandardError
      nil
    end
    FileUtils.rm_rf(tmpdir)
  end

  def accept_one_command
    Thread.new do
      conn = server.accept
      received_payloads << JSON.parse(conn.gets.chomp)
      conn.close
    end
  end

  context "when target is not registered" do
    it "returns agent_not_found" do
      result = use_case.call(target: "no-such-agent", body: "do something")
      expect(result).to eq(ok: false, error: "agent_not_found", target: "no-such-agent")
    end
  end

  context "when target is registered but socket is gone" do
    before do
      registry.register(workspace_name: "stale-agent", socket_path: "/tmp/no-such.sock", pipeline: false, epoch: "e1")
    end

    it "returns agent_unreachable" do
      result = use_case.call(target: "stale-agent", body: "do something")
      expect(result).to eq(ok: false, error: "agent_unreachable", target: "stale-agent")
    end
  end

  context "when target is registered and reachable" do
    before { registry.register(workspace_name: "homebrew-bin", socket_path: socket_path, pipeline: false, epoch: "e1") }

    it "returns ok with a generated work_item_ref" do
      t = accept_one_command
      result = use_case.call(target: "homebrew-bin", body: "update formula")
      t.join(2)

      expect(result[:ok]).to be true
      expect(result[:work_item_ref]).to match(/\AWC-d-[0-9a-f]+\z/)
    end

    it "forwards a command payload to the agent socket" do
      t = accept_one_command
      use_case.call(target: "homebrew-bin", body: "update formula")
      t.join(2)

      expect(received_payloads.length).to eq(1)
      payload = received_payloads.first
      expect(payload["type"]).to eq("command")
      expect(payload["workspace"]).to eq("homebrew-bin")
      expect(payload["body"]).to eq("update formula")
      expect(payload["dispatch_id"]).to match(/\Ad-[0-9a-f]+\z/)
    end

    it "echoes a caller-supplied work_item_ref" do
      t = accept_one_command
      result = use_case.call(target: "homebrew-bin", body: "update formula", work_item_ref: "my-ref")
      t.join(2)

      expect(result[:work_item_ref]).to eq("my-ref")
      expect(received_payloads.first["work_item_ref"]).to eq("my-ref")
    end

    it "passes from through in the forwarded command when given" do
      t = accept_one_command
      use_case.call(target: "homebrew-bin", body: "update formula", from: "workspace")
      t.join(2)

      expect(received_payloads.first["from"]).to eq("workspace")
    end

    it "omits from in the forwarded command when not given" do
      t = accept_one_command
      use_case.call(target: "homebrew-bin", body: "update formula")
      t.join(2)

      expect(received_payloads.first).not_to have_key("from")
    end
  end
end
