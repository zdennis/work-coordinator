# frozen_string_literal: true

require "json"
require "securerandom"
require "socket"
require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Adapters
    # Routes delivery to a workspace agent's Unix socket when the workspace has
    # a live registration, and to tmux otherwise.
    #
    # Registered agents receive a JSON `command` message and read it themselves;
    # unregistered workspaces still get keystrokes typed into their pane. The
    # decorator keeps the registry honest: a socket that has disappeared is
    # unregistered on the spot so the next delivery goes straight to tmux.
    class WorkspaceAgentSession
      include Ports::AgentSession

      # Raised when an agent's socket refuses connections for longer than the
      # retry budget. Deliberately not a tmux fallback — a registered agent that
      # is not answering is a condition a human needs to hear about.
      class DeliveryTimeout < StandardError; end

      # Seconds to wait between connection attempts, ~1 minute in total.
      BACKOFF_SECONDS = [1, 2, 4, 8, 16, 32].freeze

      # @param tmux [Ports::AgentSession] the session used when no agent is registered
      # @param registry [Ports::WorkspaceAgentRegistry]
      # @param sleeper [#call] waits the given number of seconds between retries
      def initialize(tmux:, registry:, sleeper: ->(seconds) { sleep(seconds) })
        @tmux = tmux
        @registry = registry
        @sleeper = sleeper
      end

      # Sends a message to the workspace's agent, or to its tmux pane.
      #
      # @param session_id [String] the workspace name
      # @param message [String]
      # @param work_item_ref [String, nil] required to address a registered
      #   agent; without it delivery always goes to tmux
      # @return [void]
      # @raise [DeliveryTimeout] when a registered agent stops answering
      def deliver(session_id:, message:, work_item_ref: nil)
        entry = work_item_ref && @registry.find(session_id)
        return @tmux.deliver(session_id: session_id, message: message) unless entry

        deliver_to_agent(
          socket_path: entry[:socket_path],
          workspace: session_id,
          work_item_ref: work_item_ref,
          body: message
        )
      rescue Errno::ENOENT
        @registry.unregister(workspace_name: session_id)
        @tmux.deliver(session_id: session_id, message: message)
      end

      # @see Ports::AgentSession#start_session
      def start_session(work_item_id:) = @tmux.start_session(work_item_id: work_item_id)

      # @see Ports::AgentSession#end_session
      def end_session(session_id:) = @tmux.end_session(session_id: session_id)

      # @see Ports::AgentSession#active_session
      def active_session(work_item_id:) = @tmux.active_session(work_item_id: work_item_id)

      # @see Ports::AgentSession#list_all_panes
      def list_all_panes = @tmux.list_all_panes

      # @see Ports::AgentSession#deliver_to_pane
      def deliver_to_pane(workspace_name:, pane_index:, message:)
        @tmux.deliver_to_pane(workspace_name: workspace_name, pane_index: pane_index, message: message)
      end

      private

      def deliver_to_agent(socket_path:, workspace:, work_item_ref:, body:)
        payload = {
          type: "command",
          workspace: workspace,
          work_item_ref: work_item_ref,
          dispatch_id: "d-#{SecureRandom.hex(8)}",
          body: body
        }
        write_payload(connect(socket_path, workspace), payload)
      end

      # Commands are fire-and-forget: the agent acknowledges by accepting the
      # write, so there is no reply to read.
      def write_payload(socket, payload)
        socket.write("#{JSON.generate(payload)}\n")
      ensure
        socket.close
      end

      def connect(socket_path, workspace)
        delays = BACKOFF_SECONDS.dup
        begin
          UNIXSocket.new(socket_path)
        rescue Errno::ECONNREFUSED
          # An agent mid-restart leaves its socket file in place with nothing
          # listening. Wait it out rather than typing into a pane it may not own.
          if delays.empty?
            raise DeliveryTimeout,
                  "workspace agent '#{workspace}' did not answer within the retry budget"
          end

          @sleeper.call(delays.shift)
          retry
        end
      end
    end
  end
end
