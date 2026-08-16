# frozen_string_literal: true

require "fileutils"
require "json"
require "socket"
require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # Listens on a Unix domain socket, treating each line as one message of the
    # form `<ref> <body>`, or — when the line starts with `{` — as one JSON
    # message. Push-style only: {#receive_messages} and {#on_message} are not
    # supported.
    class SocketMessageReceiver
      include Ports::MessageReceiver

      # JSON `type` values this receiver knows how to hand upstream.
      JSON_MESSAGE_TYPES = %w[register deregister].freeze

      # @param socket_path [String]
      def initialize(socket_path: "/tmp/work-coordinator.sock")
        @socket_path = socket_path
        @server = nil
        @stop_requested = false
      end

      # Replaces any stale socket file, then accepts connections until {#stop},
      # yielding one parsed message per connection.
      #
      # @yieldparam message [Hash] `{ work_item_ref:, body:, received_at: }` for
      #   plain lines, `{ type:, raw:, received_at: }` for JSON lines
      # @return [void]
      def start(&)
        FileUtils.rm_f(@socket_path)
        @server = UNIXServer.new(@socket_path)
        accept_loop(&)
      end

      # Closes the listener and removes the socket file, unblocking {#start}.
      # Errors during teardown are swallowed.
      #
      # @return [void]
      def stop
        @stop_requested = true
        @server&.close
        FileUtils.rm_f(@socket_path) if @socket_path
      rescue StandardError
        nil
      end

      def receive_messages(since: nil) = raise NotImplementedError
      def on_message(&) = raise NotImplementedError

      private

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

        message = parse_line(line)
        return if message.nil?

        block.call(message)
      rescue StandardError => e
        warn "[SocketMessageReceiver] dropping message: #{e.class}: #{e.message}"
      ensure
        conn.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def parse_line(line)
        return parse_json_line(line) if line.start_with?("{")

        if line.include?(" ")
          ref, body = line.split(" ", 2)
          { work_item_ref: ref, body: body, received_at: Time.now }
        else
          warn "[SocketMessageReceiver] no ref found in line; treating entire line as body"
          { work_item_ref: nil, body: line, received_at: Time.now }
        end
      end

      # @return [Hash, nil] `{ type:, raw:, received_at: }`, or nil if the line
      #   is not usable JSON or carries a type we do not handle.
      def parse_json_line(line)
        raw = JSON.parse(line)
        type = raw["type"]
        unless JSON_MESSAGE_TYPES.include?(type)
          warn "[SocketMessageReceiver] dropping JSON message with unknown type: #{type.inspect}"
          return nil
        end

        { type: type, raw: raw, received_at: Time.now }
      rescue JSON::ParserError => e
        warn "[SocketMessageReceiver] dropping malformed JSON message: #{e.message}"
        nil
      end
    end
  end
end
