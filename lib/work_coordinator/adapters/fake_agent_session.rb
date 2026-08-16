# frozen_string_literal: true

require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Adapters
    # In-memory agent session for tests. Sessions are named `session-N` and
    # delivered messages are captured rather than sent anywhere.
    class FakeAgentSession
      include Ports::AgentSession

      # @return [void]
      def initialize
        @sessions = {}        # session_id => work_item_id
        @active = {}          # work_item_id => session_id
        @messages = []
        @next_id = 0
        @all_panes = []
        @pane_deliveries = []
        @stubbed_panes = []
        @injections = []
        @inject_reply = { ok: true, queued_for_pane: 0 }
      end

      # @return [Array<Hash{Symbol=>Object}>] every {#inject} call, in order
      attr_reader :injections

      # Sets the reply {#inject} hands back.
      # @return [Hash{Symbol=>Object}]
      attr_writer :inject_reply

      # Allocates a new session identifier for the work item and activates it.
      #
      # @param work_item_id [String]
      # @return [String] the generated session id
      def start_session(work_item_id:)
        session_id = "session-#{@next_id += 1}"
        @sessions[session_id] = work_item_id
        @active[work_item_id] = session_id
        session_id
      end

      # Records the message against the session; never transmits.
      #
      # @param session_id [String]
      # @param message [String]
      # @param work_item_ref [String, nil] ignored
      # @return [void]
      def deliver(session_id:, message:, **)
        @messages << { session_id: session_id, message: message }
      end

      # Records the steer and returns the configured reply.
      #
      # @return [Hash{Symbol=>Object}]
      def inject(workspace_name:, work_item_ref:, body:, interrupt: false)
        @injections << { workspace_name: workspace_name, work_item_ref: work_item_ref,
                         body: body, interrupt: interrupt }
        @inject_reply
      end

      # Removes the session and deactivates it for the associated work item.
      #
      # @param session_id [String]
      # @return [void]
      def end_session(session_id:)
        work_item_id = @sessions.delete(session_id)
        @active.delete(work_item_id) if work_item_id
      end

      # Returns the session id currently active for the work item, if any.
      #
      # @param work_item_id [String]
      # @return [String, nil]
      def active_session(work_item_id:)
        @active[work_item_id]
      end

      # @return [Array<Hash{Symbol=>String}>] every delivery, as
      #   `{ session_id:, message: }`, in order
      def delivered_messages
        @messages.dup
      end

      # Overrides the pane list returned by {#list_all_panes}.
      #
      # @param panes [Array<String>]
      # @return [void]
      def stub_panes(panes)
        @all_panes = panes
      end

      # @return [Array<String>] configured pane identifiers, empty by default
      def list_all_panes
        @all_panes.dup
      end

      # Delivers a message to a pane, respecting the stub_pane configuration.
      #
      # @param workspace_name [String]
      # @param pane_index [Integer] 1-based domain pane index
      # @param message [String]
      # @raise [Ports::AgentSession::PaneNotFoundError] when the pane has not been stubbed
      def deliver_to_pane(workspace_name:, pane_index:, message:)
        unless pane_stubbed?(workspace_name: workspace_name, pane_index: pane_index)
          raise Ports::AgentSession::PaneNotFoundError,
                "pane #{pane_index} not stubbed for session '#{workspace_name}'"
        end

        @pane_deliveries << { workspace_name: workspace_name, pane_index: pane_index, message: message }
      end

      # Returns all deliver_to_pane calls recorded so far, in order.
      #
      # @return [Array<Hash{Symbol=>Object}>] each entry has :workspace_name, :pane_index, :message
      def delivered_to_pane
        @pane_deliveries.dup
      end

      # Configures a pane as present for deliver_to_pane existence checks.
      #
      # @param workspace_name [String]
      # @param pane_index [Integer] 1-based domain pane index
      def stub_pane(workspace_name:, pane_index:)
        @stubbed_panes << { workspace_name: workspace_name, pane_index: pane_index }
      end

      private

      def pane_stubbed?(workspace_name:, pane_index:)
        @stubbed_panes.any? { |p| p[:workspace_name] == workspace_name && p[:pane_index] == pane_index }
      end
    end
  end
end
