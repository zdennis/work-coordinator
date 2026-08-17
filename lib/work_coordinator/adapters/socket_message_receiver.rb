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

      # Version of the agent/coordinator message protocol this receiver speaks.
      PROTOCOL_VERSION = "1"

      # JSON `type` values this receiver knows how to hand upstream.
      JSON_MESSAGE_TYPES = %w[register deregister command_v1 dispatch].freeze

      # JSON `type` values answered on the connection instead of yielded.
      REGISTRATION_TYPES = %w[register deregister].freeze

      # JSON `type` values answered on the connection via an injected handler.
      DISPATCH_TYPES = %w[dispatch].freeze

      # Envelope fields lifted onto a parsed `command_v1` message.
      COMMAND_FIELDS = %w[role verb workspace instructions work_item_ref source].freeze

      # @param socket_path [String]
      # @param workspace_agent_registry [Ports::WorkspaceAgentRegistry, nil] when
      #   given, register/deregister messages are answered here and are not
      #   handed upstream
      # @param dispatch_handler [#call, nil] when given, dispatch messages are
      #   answered here instead of being handed upstream; called with
      #   `(target:, body:, work_item_ref:, from:)` and must return a Hash
      # How often (seconds) the accept loop wakes up to check whether the socket
      # file still exists on disk.
      DEFAULT_WATCHDOG_INTERVAL = 5

      def initialize(socket_path: "/tmp/work-coordinator.sock", workspace_agent_registry: nil,
                     dispatch_handler: nil, watchdog_interval: DEFAULT_WATCHDOG_INTERVAL)
        @socket_path = socket_path
        @workspace_agent_registry = workspace_agent_registry
        @dispatch_handler = dispatch_handler
        @watchdog_interval = watchdog_interval
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
      # Existing registrations are intentionally preserved across restarts.
      # Agents that are still running will have valid entries in the registry;
      # stale entries for dead agents are cleaned up lazily by
      # {WorkspaceAgentSession} when the first delivery attempt fails with
      # Errno::ENOENT.
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
          conn = accept_connection
          next if conn == :watchdog_tick
          break unless conn

          handle_connection(conn, &)
        end
      end

      def accept_connection
        unless @server.wait_readable(@watchdog_interval)
          ensure_socket_alive
          return :watchdog_tick
        end

        @server.accept
      rescue IOError, Errno::EBADF
        nil
      end

      def ensure_socket_alive
        return if @stop_requested || File.exist?(@socket_path)

        warn "[SocketMessageReceiver] socket file missing, recreating: #{@socket_path}"
        @server.close rescue nil # rubocop:disable Style/RescueModifier
        @server = UNIXServer.new(@socket_path)
      end

      def handle_connection(conn, &block)
        message = read_message(conn)
        return if message.nil?
        return reply(conn, handle_registration(message[:raw])) if registration?(message)
        return if dispatch_consumed?(conn, message)

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
        @workspace_agent_registry && REGISTRATION_TYPES.include?(message[:type])
      end

      # Returns true when the message was consumed — either dispatched or silently
      # dropped because it is a dispatch type but no handler is configured.
      def dispatch_consumed?(conn, message)
        return false unless dispatch_type?(message)

        reply(conn, handle_dispatch(message[:raw])) if dispatchable?(message)
        true
      end

      def dispatchable?(message)
        @dispatch_handler && dispatch_type?(message)
      end

      def dispatch_type?(message)
        DISPATCH_TYPES.include?(message[:type])
      end

      def handle_dispatch(raw)
        @dispatch_handler.call(
          target: raw["target"],
          body: raw["body"],
          work_item_ref: raw["work_item_ref"],
          from: raw["from"]
        )
      rescue StandardError => e
        warn "[SocketMessageReceiver] dispatch handler raised: #{e.class}: #{e.message}"
        { ok: false, error: "internal_error" }
      end

      def reply(conn, payload)
        conn.puts(JSON.generate(payload))
      end

      # Answers a register/deregister message. The agent waits on this reply, so
      # it is written on the same connection before it is closed.
      #
      # @return [Hash] `{ok: true, epoch:, protocol_version:}`, `{ok: true}`, or
      #   `{ok: false, error:}`
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
        result[:ok] ? { ok: true, epoch: @epoch, protocol_version: PROTOCOL_VERSION } : result
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

        return parse_command(raw) if type == "command_v1"

        { type: type, raw: raw, received_at: Time.now }
      rescue JSON::ParserError => e
        warn "[SocketMessageReceiver] dropping malformed JSON message: #{e.message}"
        nil
      end

      # A `command_v1` envelope carries the whole request in its fields, so it is
      # flattened here rather than left for every consumer to dig out of `raw`.
      #
      # @return [Hash, nil] nil when `instructions` is missing — there is nothing
      #   to run without it.
      def parse_command(raw)
        if raw["instructions"].nil?
          warn "[SocketMessageReceiver] dropping command_v1 message without instructions"
          return nil
        end

        fields = COMMAND_FIELDS.to_h { |field| [field.to_sym, raw[field]] }
        fields.merge(type: "command_v1", raw: raw, received_at: Time.now)
      end
    end
  end
end
