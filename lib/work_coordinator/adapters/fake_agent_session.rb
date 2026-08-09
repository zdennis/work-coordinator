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
      end

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
      # @return [void]
      def deliver(session_id:, message:)
        @messages << { session_id: session_id, message: message }
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
    end
  end
end
