# frozen_string_literal: true

module WorkCoordinator
  # Port interfaces that the domain and application layers depend on.
  module Ports
    # Interface for driving the agent process attached to a work item.
    #
    # Implementors own the mapping between work items and live sessions: a
    # session identifier returned by {#start_session} must remain valid for
    # {#deliver} until {#end_session} is called, and {#active_session} must
    # return that same identifier for as long as the session is reachable.
    module AgentSession
      # Raised when a requested pane does not exist in the named session.
      class PaneNotFoundError < StandardError; end

      # @param work_item_id [String]
      # @return [String] identifier of the newly opened session
      def start_session(work_item_id:) = raise NotImplementedError

      # Sends a message into a running session.
      #
      # Implementors that address the agent directly (rather than typing into a
      # pane) need `work_item_ref` to say which item the message belongs to;
      # pane-based implementors ignore it.
      #
      # @param session_id [String]
      # @param message [String]
      # @param work_item_ref [String, nil]
      # @return [void]
      def deliver(session_id:, message:, work_item_ref: nil) = raise NotImplementedError

      # Tears down a session, releasing whatever the implementor holds for it.
      #
      # @param session_id [String]
      # @return [void]
      def end_session(session_id:) = raise NotImplementedError

      # @param work_item_id [String]
      # @return [String, nil] session identifier, or nil when no session is live
      def active_session(work_item_id:) = raise NotImplementedError

      # @return [Array<String>] all currently active pane identifiers
      def list_all_panes = raise NotImplementedError

      # Delivers a message directly to a specific pane of an already-running session.
      #
      # @param workspace_name [String] the tmux session name
      # @param pane_index [Integer] 1-based pane index (1 = the first pane in the session)
      # @param message [String]
      # @return [void]
      # @raise [PaneNotFoundError] when the specified pane does not exist in the session
      def deliver_to_pane(workspace_name:, pane_index:, message:) = raise NotImplementedError
    end
  end
end
