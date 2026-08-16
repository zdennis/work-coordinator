# frozen_string_literal: true

require "json"
require "logger"
require "securerandom"
require "socket"

module WorkCoordinator
  module Adapters
    # Tells every registered workspace agent that the coordinator has restarted.
    # Unreachable agents are logged and skipped — a restart notice is advisory.
    class AgentRestartNotifier
      def initialize(registry:, logger: Logger.new(IO::NULL))
        @registry = registry
        @logger = logger
      end

      # @return [void]
      def notify_all
        @registry.all.each { |entry| notify_one(entry) }
      end

      private

      def notify_one(entry)
        socket = UNIXSocket.new(entry[:socket_path])
        payload = { type: "coordinator_restart", dispatch_id: "d-#{SecureRandom.hex(8)}" }
        socket.write("#{JSON.generate(payload)}\n")
      rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPIPE => e
        @logger.debug "AgentRestartNotifier: could not reach #{entry[:workspace_name].inspect}: #{e.message}"
      ensure
        socket&.close
      end
    end
  end
end
