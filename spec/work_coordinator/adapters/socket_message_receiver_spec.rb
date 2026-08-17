# frozen_string_literal: true

require "socket"
require "tmpdir"
require "work_coordinator/adapters/fake_workspace_agent_registry"
require "work_coordinator/adapters/socket_message_receiver"

RSpec.describe WorkCoordinator::Adapters::SocketMessageReceiver do
  describe "#stop" do
    subject(:receiver) { described_class.new }

    it "does not raise when called before start" do
      expect { receiver.stop }.not_to raise_error
    end
  end

  describe "#start" do
    subject(:receiver) { described_class.new(socket_path: socket_path) }

    let(:tmpdir) { Dir.mktmpdir }
    let(:socket_path) { File.join(tmpdir, "test.sock") }
    let(:delivered) { Queue.new }
    let(:listeners) { [] }

    after do
      receiver.stop
      listeners.each { |thread| thread.join(2) }
      FileUtils.remove_entry(tmpdir)
    end

    def send_line(line)
      UNIXSocket.open(socket_path) do |client|
        client.puts(line)
      end
    end

    def wait_for_socket
      20.times do
        break if File.socket?(socket_path)

        sleep 0.05
      end
    end

    def start_listener
      listeners << Thread.new do
        receiver.start { |message| delivered << message }
      end
      wait_for_socket
    end

    it "yields ref and body for a plain line" do
      start_listener

      send_line("WC-42 some body")

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(work_item_ref: "WC-42", body: "some body")
      expect(message[:received_at]).to be_a(Time)
    end

    context "with a workspace agent registry" do
      subject(:receiver) do
        described_class.new(socket_path: socket_path, workspace_agent_registry: registry)
      end

      let(:registry) { WorkCoordinator::Adapters::FakeWorkspaceAgentRegistry.new }

      def request(line)
        UNIXSocket.open(socket_path) do |client|
          client.puts(line)
          JSON.parse(Timeout.timeout(2) { client.gets })
        end
      end

      def register_line(name: "myapp", epoch: "wa-1")
        JSON.generate("type" => "register", "name" => name, "socket" => "/tmp/workspace-#{name}.sock",
                      "pipeline" => true, "epoch" => epoch)
      end

      it "replies with the coordinator epoch and protocol version, and records the registration" do
        start_listener

        expect(request(register_line)).to eq("ok" => true, "epoch" => receiver.epoch,
                                             "protocol_version" => "1")
        expect(registry.find("myapp")).to eq(socket_path: "/tmp/workspace-myapp.sock",
                                             pipeline: true, epoch: "wa-1")
      end

      it "refuses a workspace already claimed by another process" do
        start_listener
        request(register_line)

        expect(request(register_line(epoch: "wa-2"))).to eq("ok" => false, "error" => "already_registered")
      end

      it "replies ok to deregister and drops the registration" do
        start_listener
        request(register_line)

        expect(request('{"type":"deregister","name":"myapp"}')).to eq("ok" => true)
        expect(registry.registered?("myapp")).to be(false)
      end

      it "does not yield registration messages upstream" do
        start_listener

        request(register_line)
        send_line("WC-7 after register")

        expect(Timeout.timeout(2) { delivered.pop }).to include(work_item_ref: "WC-7")
      end

      it "drops registrations left behind by a previous coordinator process" do
        registry.register(workspace_name: "myapp", socket_path: "/tmp/stale.sock",
                          pipeline: true, epoch: "wa-old")
        start_listener

        expect(registry.registered?("myapp")).to be(false)
      end
    end

    it "yields a structured message for a JSON line" do
      start_listener

      send_line('{"type":"register","name":"myapp","socket":"/tmp/workspace-myapp.sock","pipeline":true}')

      message = Timeout.timeout(2) { delivered.pop }
      expect(message[:type]).to eq("register")
      expect(message[:raw]).to eq(
        "type" => "register",
        "name" => "myapp",
        "socket" => "/tmp/workspace-myapp.sock",
        "pipeline" => true
      )
      expect(message[:received_at]).to be_a(Time)
      expect(message).not_to have_key(:work_item_ref)
    end

    it "yields a flattened message for a command_v1 line" do
      start_listener

      send_line(JSON.generate("version" => "1", "type" => "command_v1", "role" => "home",
                              "verb" => "claude", "workspace" => "MS",
                              "instructions" => "add validation",
                              "work_item_ref" => "WC-42", "source" => "socket"))

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(type: "command_v1", role: "home", verb: "claude",
                                 workspace: "MS", instructions: "add validation",
                                 work_item_ref: "WC-42", source: "socket")
      expect(message[:received_at]).to be_a(Time)
    end

    it "leaves optional command_v1 fields nil" do
      start_listener

      send_line('{"type":"command_v1","instructions":"just do it"}')

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(instructions: "just do it", role: nil, verb: nil,
                                 workspace: nil, work_item_ref: nil, source: nil)
    end

    it "drops a command_v1 line without instructions" do
      start_listener

      send_line('{"type":"command_v1","verb":"claude"}')
      send_line("WC-8 after dropped command")

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(work_item_ref: "WC-8", body: "after dropped command")
    end

    it "drops a JSON line with an unknown type without yielding" do
      start_listener

      send_line('{"type":"nonsense"}')
      send_line("WC-7 after unknown")

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(work_item_ref: "WC-7", body: "after unknown")
    end

    it "keeps accepting messages after malformed JSON" do
      start_listener

      send_line("{broken")
      send_line("WC-9 after malformed")

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(work_item_ref: "WC-9", body: "after malformed")
    end

    it "keeps accepting messages after a handler raises" do
      listeners << Thread.new do
        receiver.start do |message|
          raise "handler blew up" if message[:body] == "boom"

          delivered << message
        end
      end
      wait_for_socket

      send_line("wi-1 boom")
      send_line("wi-2 still here")

      message = Timeout.timeout(2) { delivered.pop }
      expect(message).to include(work_item_ref: "wi-2", body: "still here")
    end

    describe "dispatch messages" do
      subject(:receiver) do
        described_class.new(socket_path: socket_path, dispatch_handler: dispatch_handler)
      end

      let(:dispatch_results) { Queue.new }
      let(:dispatch_handler) do
        lambda do |target:, body:, work_item_ref:, from:|
          { ok: true, work_item_ref: work_item_ref || "WC-d-generated", _args: { target:, body:, from: } }
        end
      end

      def send_dispatch(payload)
        UNIXSocket.open(socket_path) do |client|
          client.puts(JSON.generate(payload))
          client.gets
        end
      end

      def start_capturing_receiver(path, &handler)
        r = described_class.new(socket_path: path, dispatch_handler: handler)
        t = Thread.new { r.start { |_m| nil } }
        20.times do
          break if File.socket?(path)

          sleep 0.05
        end
        [r, t]
      end

      before { start_listener }

      it "answers the connection with the dispatch handler result" do
        reply_line = send_dispatch({ type: "dispatch", target: "homebrew-bin", body: "update formula" })
        reply = JSON.parse(reply_line, symbolize_names: true)
        expect(reply[:ok]).to be true
      end

      it "passes target, body, work_item_ref, and from to the handler" do
        received = nil
        cap_path = File.join(tmpdir, "cap.sock")
        r, t = start_capturing_receiver(cap_path) do |target:, body:, work_item_ref:, from:|
          received = { target:, body:, work_item_ref:, from: }
          { ok: true, work_item_ref: "WC-d-x" }
        end
        UNIXSocket.open(cap_path) do |c|
          c.puts(JSON.generate({ type: "dispatch", target: "app", body: "do it",
                                 work_item_ref: "WC-42", from: "workspace" }))
          c.gets
        end
        r.stop
        t.join(2)

        expect(received).to eq(target: "app", body: "do it", work_item_ref: "WC-42", from: "workspace")
      end

      it "does not yield dispatch messages upstream" do
        send_dispatch({ type: "dispatch", target: "homebrew-bin", body: "update formula" })
        expect(delivered.empty?).to be true
      end

      it "drops dispatch messages when no dispatch_handler is configured" do
        plain_receiver = described_class.new(socket_path: File.join(tmpdir, "plain.sock"))
        plain_thread = Thread.new { plain_receiver.start { |m| delivered << m } }
        20.times do
          break if File.socket?(File.join(tmpdir, "plain.sock"))

          sleep 0.05
        end
        UNIXSocket.open(File.join(tmpdir, "plain.sock")) do |c|
          c.puts(JSON.generate({ type: "dispatch", target: "x", body: "y" }))
        end
        plain_receiver.stop
        plain_thread.join(2)
        expect(delivered.empty?).to be true
      end
    end
  end
end
