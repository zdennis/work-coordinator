# frozen_string_literal: true

require "fileutils"
require "socket"
require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    class SocketMessageReceiver
      include Ports::MessageReceiver

      def initialize(socket_path: "/tmp/work-coordinator.sock")
        @socket_path = socket_path
        @server = nil
        @stop_requested = false
      end

      def start(&)
        FileUtils.rm_f(@socket_path)
        @server = UNIXServer.new(@socket_path)
        install_signal_traps
        accept_loop(&)
      end

      def stop
        @stop_requested = true
        @server&.close
      rescue StandardError
        nil
      end

      def receive_messages(since: nil) = raise NotImplementedError
      def on_message(&) = raise NotImplementedError

      private

      def install_signal_traps
        trap("TERM") { stop }
        trap("INT")  { stop }
      end

      def accept_loop(&)
        until @stop_requested
          conn = accept_connection || break
          handle_connection(conn, &)
        end
      end

      def accept_connection
        @server.accept
      rescue IOError, Errno::EBADF
        nil
      end

      def handle_connection(conn, &block)
        line = conn.gets&.chomp
        return if line.nil? || line.empty?

        block.call(parse_line(line))
      ensure
        conn.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def parse_line(line)
        if line.include?(" ")
          ref, body = line.split(" ", 2)
          { work_item_ref: ref, body: body, received_at: Time.now }
        else
          warn "[SocketMessageReceiver] no ref found in line; treating entire line as body"
          { work_item_ref: nil, body: line, received_at: Time.now }
        end
      end
    end
  end
end
