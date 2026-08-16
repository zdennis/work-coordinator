# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
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
      # @param workspace_agent_registry [Ports::WorkspaceAgentRegistry, nil] when
      #   given, register/deregister messages are answered here and are not
      #   handed upstream
      def initialize(socket_path: "/tmp/work-coordinator.sock", workspace_agent_registry: nil)
        @socket_path = socket_path
        @workspace_agent_registry = workspace_agent_registry
        @epoch = "wc-#{SecureRandom.hex(8)}"
        @server = nil
        @stop_requested = false
      end

      # @return [String] identifier for this listener's lifetime, echoed in every ok reply
      attr_reader :epoch

      # Replaces any stale socket file, then accepts connections until {#stop},
      # yielding one parsed message per connection. Register and deregister
      # messages are answered here instead of being yielded — the agent blocks
      # on the reply, so it has to be written before the connection closes.
      #
      # @yieldparam message [Hash] `{ work_item_ref:, body:, received_at: }` for
      #   plain lines, `{ type:, raw:, received_at: }` for JSON lines
      # @return [void]
      def start(&)
        @workspace_agent_registry&.clear
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
        message = read_message(conn)
        return if message.nil?
        return reply(conn, handle_registration(message[:raw])) if registration?(message)

        block.call(message)
      rescue StandardError => e
        warn "[SocketMessageReceiver] dropping message: #{e.class}: #{e.message}"
      ensure
        conn.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def read_message(conn)
        line = conn.gets&.chomp
        return nil if line.nil? || line.empty?

        parse_line(line)
      end

      def registration?(message)
        @workspace_agent_registry && JSON_MESSAGE_TYPES.include?(message[:type])
      end

      def reply(conn, payload)
        conn.puts(JSON.generate(payload))
      end

      # Answers a register/deregister message. The agent waits on this reply, so
      # it is written on the same connection before it is closed.
      #
      # @return [Hash] `{ok: true, epoch:}`, `{ok: true}`, or `{ok: false, error:}`
      def handle_registration(raw)
        case raw["type"]
        when "register"   then handle_register(raw)
        when "deregister" then @workspace_agent_registry.unregister(workspace_name: raw["name"])
        end
      end

      def handle_register(raw)
        result = @workspace_agent_registry.register(
          workspace_name: raw["name"],
          socket_path: raw["socket"],
          pipeline: raw["pipeline"] ? true : false,
          epoch: raw["epoch"]
        )
        result[:ok] ? { ok: true, epoch: @epoch } : result
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
