# frozen_string_literal: true

require "json"
require "socket"
require "tmpdir"
require "work_coordinator/adapters/workspace_status_receiver"
require "support/fake_complete_work_item"
require "support/fake_notify_human"
require "support/fake_inform_human"

RSpec.describe WorkCoordinator::Adapters::WorkspaceStatusReceiver do
  subject(:receiver) do
    described_class.new(
      socket_path: socket_path,
      work_item_repo: work_item_repo,
      event_store: event_store,
      complete_work_item: complete_work_item,
      notify_human: notify_human,
      inform_human: inform_human
    )
  end

  let(:tmpdir) { Dir.mktmpdir }
  let(:socket_path) { File.join(tmpdir, "status.sock") }
  let(:work_item_repo) { WorkCoordinator::Adapters::InMemoryWorkItemRepository.new }
  let(:event_store) { WorkCoordinator::Application::InMemoryEventStore.new }
  let(:complete_work_item) { FakeCompleteWorkItem.new }
  let(:notify_human) { FakeNotifyHuman.new }
  let(:inform_human) { FakeInformHuman.new }
  let(:listeners) { [] }

  let(:work_item) do
    build(:work_item_domain, id: "wi-1", external_reference: "WC-42", state: :active, workspace_name: "myapp")
  end

  before do
    work_item_repo.save(work_item)
    start_listener
  end

  after do
    receiver.stop
    listeners.each { |thread| thread.join(2) }
    FileUtils.remove_entry(tmpdir)
  end

  def start_listener
    listeners << Thread.new { receiver.start }
    20.times do
      break if File.socket?(socket_path)

      sleep 0.05
    end
  end

  # Stands in for a workspace agent: one connection, one JSON line, one reply.
  def send_status(payload)
    Timeout.timeout(2) do
      UNIXSocket.open(socket_path) do |client|
        client.puts(payload.is_a?(String) ? payload : JSON.generate(payload))
        line = client.gets
        line && JSON.parse(line)
      end
    end
  end

  def base(type, message_id:, sequence: 1, **rest)
    { type: type, workspace: "myapp", work_item_ref: "WC-42", message_id: message_id, sequence: sequence, **rest }
  end

  describe "status_update" do
    it "appends an agent.status_update event and acks" do
      reply = send_status(base("status_update", message_id: "m1", message: "running specs"))

      expect(reply).to include("ok" => true)
      expect(reply["epoch"]).to start_with("wc-")

      event = event_store.last_of_type(type: "agent.status_update")
      expect(event.work_item_id).to eq("wi-1")
      expect(event.data).to include(workspace: "myapp", work_item_ref: "WC-42", message: "running specs",
                                    message_id: "m1")
    end
  end

  describe "phase_change" do
    it "updates the work item phase and appends an event" do
      reply = send_status(base("phase_change", message_id: "m1", phase: "review"))

      expect(reply).to include("ok" => true)
      expect(work_item_repo.find("wi-1").phase).to eq("review")

      event = event_store.last_of_type(type: "agent.phase_changed")
      expect(event.data).to include(phase: "review", workspace: "myapp")
    end
  end

  describe "pipeline_advanced" do
    it "appends an agent.pipeline_advanced event" do
      reply = send_status(base("pipeline_advanced", message_id: "m1", from_pane: "dev", to_pane: "review"))

      expect(reply).to include("ok" => true)

      event = event_store.last_of_type(type: "agent.pipeline_advanced")
      expect(event.data).to include(from_pane: "dev", to_pane: "review", message_id: "m1")
    end
  end

  describe "task_complete" do
    it "completes the work item" do
      reply = send_status(base("task_complete", message_id: "m1", summary: "shipped"))

      expect(reply).to include("ok" => true)
      expect(complete_work_item.calls).to eq([{ work_item_id: "wi-1", summary: "shipped" }])
    end
  end

  describe "error" do
    it "informs the human without changing state" do
      reply = send_status(base("error", message_id: "m1", message: "build failed"))

      expect(reply).to include("ok" => true)
      expect(notify_human.calls).to be_empty
      expect(inform_human.calls.map { |c| c.slice(:work_item_id, :body) })
        .to eq([{ work_item_id: "wi-1", body: "build failed" }])
      expect(work_item_repo.find(work_item.id).state).to eq(:active)
    end
  end

  describe "unknown type" do
    it "acks without processing" do
      reply = send_status(base("nonsense", message_id: "m1"))

      expect(reply).to include("ok" => true)
      expect(event_store.all).to be_empty
    end
  end

  describe "unknown work item" do
    it "tells the sender to give up" do
      reply = send_status(base("status_update", message_id: "m1", work_item_ref: "WC-999", message: "hi"))

      expect(reply).to eq("ok" => false, "error" => "unknown_work_item", "ref" => "WC-999", "action" => "give_up")
    end
  end

  describe "terminal work item" do
    it "tells the sender to abort the pipeline" do
      work_item_repo.save(work_item.with(state: :completed))

      reply = send_status(base("status_update", message_id: "m1", message: "hi"))

      expect(reply).to eq("ok" => false, "error" => "terminal_state", "state" => "completed",
                          "action" => "abort_pipeline")
    end
  end

  describe "duplicate message_id" do
    it "acks idempotently without reprocessing" do
      send_status(base("status_update", message_id: "m1", sequence: 1, message: "first"))
      reply = send_status(base("status_update", message_id: "m1", sequence: 2, message: "again"))

      expect(reply).to include("ok" => true)
      expect(event_store.all.size).to eq(1)
    end
  end

  describe "out-of-sequence message" do
    it "rejects the message and does not process it" do
      send_status(base("status_update", message_id: "m1", sequence: 5, message: "first"))
      reply = send_status(base("status_update", message_id: "m2", sequence: 3, message: "stale"))

      expect(reply).to eq("ok" => false, "error" => "out_of_sequence", "last_sequence" => 5, "action" => "drop")
      expect(event_store.all.size).to eq(1)
    end
  end

  describe "malformed JSON" do
    it "stays alive and processes the next valid message" do
      send_status("{broken")

      reply = send_status(base("status_update", message_id: "m1", message: "after"))

      expect(reply).to include("ok" => true)
      expect(event_store.all.size).to eq(1)
    end
  end

  describe "internal error during dispatch" do
    subject(:receiver) do
      described_class.new(
        socket_path: socket_path,
        work_item_repo: work_item_repo,
        event_store: event_store,
        complete_work_item: complete_work_item,
        notify_human: notify_human,
        inform_human: exploding_inform_human
      )
    end

    let(:exploding_inform_human) do
      ->(**) { raise "boom" }
    end

    it "sends an error reply instead of closing without responding" do
      reply = send_status(base("status_update", message_id: "m1", message: "hi"))
      expect(reply).to include("ok" => false, "error" => "internal_error")
    end

    it "stays alive after the error so subsequent connections are accepted" do
      send_status(base("status_update", message_id: "m1", message: "boom"))
      # A second connection succeeds — the server did not crash
      reply = send_status(base("status_update", message_id: "m2", message: "boom again"))
      expect(reply).to include("ok" => false, "error" => "internal_error")
    end
  end

  describe "socket file recovery" do
    subject(:recovery_receiver) do
      described_class.new(
        socket_path: recovery_socket_path,
        work_item_repo: work_item_repo,
        event_store: event_store,
        complete_work_item: complete_work_item,
        notify_human: notify_human,
        inform_human: inform_human,
        watchdog_interval: 0.05
      )
    end

    let(:recovery_socket_path) { File.join(tmpdir, "recovery-status.sock") }

    before do
      listeners << Thread.new { recovery_receiver.start }
      20.times do
        break if File.socket?(recovery_socket_path)

        sleep 0.05
      end
    end

    after { recovery_receiver.stop }

    def send_recovery_status(payload)
      Timeout.timeout(2) do
        UNIXSocket.open(recovery_socket_path) do |client|
          client.puts(payload.is_a?(String) ? payload : JSON.generate(payload))
          line = client.gets
          line && JSON.parse(line)
        end
      end
    end

    it "recreates the socket file and continues accepting connections when deleted while running" do
      File.delete(recovery_socket_path)
      40.times do
        break if File.socket?(recovery_socket_path)

        sleep 0.05
      end

      reply = send_recovery_status(base("status_update", message_id: "recovery-1", message: "after recovery"))
      expect(reply).to include("ok" => true)
      expect(inform_human.calls).not_to be_empty
    end
  end
end
