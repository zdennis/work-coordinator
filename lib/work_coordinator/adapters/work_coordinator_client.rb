# frozen_string_literal: true

require "json"
require "socket"

module WorkCoordinator
  module Adapters
    # Thin client for talking to a running coordinator over its main Unix socket.
    # Each method opens a fresh connection, writes one JSON message, and reads
    # back the reply.
    class WorkCoordinatorClient
      # @param socket_path [String]
      def initialize(socket_path: ENV.fetch("WC_SOCKET", "/tmp/work-coordinator.sock"))
        @socket_path = socket_path
      end

      # Asks the coordinator to forward a command to a named registered agent.
      #
      # @param name [String] the target agent's registered name
      # @param body [String] the command text to forward
      # @param work_item_ref [String, nil] caller-supplied ref; coordinator generates one when absent
      # @param from [String, nil] originating agent name for audit/logging
      # @return [Hash] coordinator reply with symbolized keys, e.g.
      #   `{ok: true, work_item_ref: "WC-d-..."}` or
      #   `{ok: false, error: "agent_not_found", target: "..."}`
      # @raise [Errno::ENOENT, Errno::ECONNREFUSED] when the coordinator socket is unreachable
      def dispatch_to(name:, body:, work_item_ref: nil, from: nil)
        payload = { type: "dispatch", target: name, body: body }
        payload[:work_item_ref] = work_item_ref if work_item_ref
        payload[:from] = from if from
        exchange(payload)
      end

      private

      def exchange(payload)
        socket = UNIXSocket.new(@socket_path)
        socket.write("#{JSON.generate(payload)}\n")
        line = socket.gets
        return { ok: false, error: "no_reply" } unless line

        JSON.parse(line, symbolize_names: true)
      rescue JSON::ParserError
        { ok: false, error: "malformed_reply" }
      ensure
        socket&.close
      end
    end
  end
end
