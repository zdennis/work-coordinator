# frozen_string_literal: true

require "json"
require "logger"
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
      # @param logger [Logger]
      def initialize(tmux:, registry:, sleeper: ->(seconds) { sleep(seconds) },
                     logger: Logger.new(IO::NULL), tmux_fallback_enabled: true)
        @tmux = tmux
        @registry = registry
        @sleeper = sleeper
        @logger = logger
        @tmux_fallback_enabled = tmux_fallback_enabled
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
        @logger.debug "WorkspaceAgentSession#deliver: workspace=#{session_id.inspect} " \
                      "has_registry=#{entry ? true : false}"
        return @tmux.deliver(session_id: session_id, message: message) unless entry

        deliver_to_agent(
          socket_path: entry[:socket_path],
          workspace: session_id,
          work_item_ref: work_item_ref,
          body: message
        )
      rescue Errno::ENOENT
        handle_missing_socket(session_id: session_id, message: message)
      end

      # Steers a registered agent mid-pipeline and waits for its answer.
      #
      # There is no tmux fallback and no retry: a steer is only meaningful
      # while the pipeline it interrupts is still running, so a slow or absent
      # agent is reported back rather than waited out.
      #
      # @see Ports::AgentSession#inject
      def inject(workspace_name:, work_item_ref:, body:, interrupt: false)
        entry = @registry.find(workspace_name)
        return { ok: false, error: "no_registration" } unless entry

        exchange(
          UNIXSocket.new(entry[:socket_path]),
          payload(type: "inject", workspace: workspace_name, work_item_ref: work_item_ref, body: body)
            .merge(interrupt: interrupt)
        )
      rescue Errno::ENOENT
        @logger.debug "WorkspaceAgentSession#inject: socket gone for workspace=#{workspace_name.inspect}, unregistering"
        @registry.unregister(workspace_name: workspace_name)
        { ok: false, error: "agent_gone" }
      rescue Errno::ECONNREFUSED
        { ok: false, error: "agent_unavailable" }
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

      def handle_missing_socket(session_id:, message:)
        raise unless @tmux_fallback_enabled

        @logger.debug "WorkspaceAgentSession#deliver: socket gone for workspace=#{session_id.inspect}, " \
                      "unregistering and falling back to tmux"
        @registry.unregister(workspace_name: session_id)
        @tmux.deliver(session_id: session_id, message: message)
      end

      def deliver_to_agent(socket_path:, workspace:, work_item_ref:, body:)
        write_payload(
          connect(socket_path, workspace),
          payload(type: "command", workspace: workspace, work_item_ref: work_item_ref, body: body)
        )
      end

      def payload(type:, workspace:, work_item_ref:, body:)
        {
          type: type,
          workspace: workspace,
          work_item_ref: work_item_ref,
          dispatch_id: "d-#{SecureRandom.hex(8)}",
          body: body
        }
      end

      # Commands are fire-and-forget: the agent acknowledges by accepting the
      # write, so there is no reply to read.
      def write_payload(socket, payload)
        socket.write("#{JSON.generate(payload)}\n")
      ensure
        socket.close
      end

      # Writes the payload and reads the agent's single-line reply.
      def exchange(socket, payload)
        socket.write("#{JSON.generate(payload)}\n")
        line = socket.gets
        return { ok: false, error: "no_reply" } unless line

        JSON.parse(line, symbolize_names: true)
      rescue JSON::ParserError
        { ok: false, error: "malformed_reply" }
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
