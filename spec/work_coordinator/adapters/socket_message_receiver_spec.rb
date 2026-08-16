# frozen_string_literal: true

require "socket"
require "tmpdir"
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
  end
end
