# frozen_string_literal: true

require "json"
require "logger"
require "securerandom"
require "socket"

module WorkCoordinator
  module Application
    # Forwards a command to a named workspace agent's socket on behalf of any
    # caller (another agent, a CLI client, etc.). The coordinator looks up the
    # target by name, writes a `command` JSON message to its socket, and returns
    # a structured result — it does NOT register a work item for the dispatched
    # command.
    class DispatchToAgent
      # @param registry [Ports::WorkspaceAgentRegistry]
      # @param logger [Logger]
      def initialize(registry:, logger: Logger.new(IO::NULL))
        @registry = registry
        @logger   = logger
      end

      # @param target [String] registered agent name
      # @param body [String] command text to forward
      # @param work_item_ref [String, nil] caller-supplied ref; generated when absent
      # @param from [String, nil] originating agent name, for audit/logging
      # @return [Hash] `{ok: true, work_item_ref: String}` or
      #   `{ok: false, error: String, target: String}`
      def call(target:, body:, work_item_ref: nil, from: nil)
        entry = @registry.find(target)
        unless entry
          @logger.debug "DispatchToAgent: target=#{target.inspect} not found in registry"
          return { ok: false, error: "agent_not_found", target: target }
        end

        ref = work_item_ref || generate_ref
        @logger.debug "DispatchToAgent: dispatching ref=#{ref} to target=#{target.inspect}"

        write_command(entry[:socket_path], target, ref, body, from)
        { ok: true, work_item_ref: ref }
      rescue Errno::ENOENT, Errno::ECONNREFUSED => e
        @logger.debug "DispatchToAgent: socket unreachable for target=#{target.inspect}: #{e.class}"
        { ok: false, error: "agent_unreachable", target: target }
      end

      private

      def write_command(socket_path, workspace, work_item_ref, body, from)
        payload = {
          type: "command",
          workspace: workspace,
          work_item_ref: work_item_ref,
          dispatch_id: "d-#{SecureRandom.hex(8)}",
          body: body
        }
        payload[:from] = from if from
        socket = UNIXSocket.new(socket_path)
        socket.write("#{JSON.generate(payload)}\n")
      ensure
        socket&.close
      end

      def generate_ref
        "WC-d-#{SecureRandom.hex(8)}"
      end
    end
  end
end
