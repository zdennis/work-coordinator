# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for driving the agent process attached to a work item.
    #
    # Implementors own the mapping between work items and live sessions: a
    # session identifier returned by {#start_session} must remain valid for
    # {#deliver} until {#end_session} is called, and {#active_session} must
    # return that same identifier for as long as the session is reachable.
    module AgentSession
      # @param work_item_id [String]
      # @return [String] identifier of the newly opened session
      def start_session(work_item_id:) = raise NotImplementedError

      # Sends a message into a running session.
      #
      # @param session_id [String]
      # @param message [String]
      # @return [void]
      def deliver(session_id:, message:) = raise NotImplementedError

      # Tears down a session, releasing whatever the implementor holds for it.
      #
      # @param session_id [String]
      # @return [void]
      def end_session(session_id:) = raise NotImplementedError

      # @param work_item_id [String]
      # @return [String, nil] session identifier, or nil when no session is live
      def active_session(work_item_id:) = raise NotImplementedError
    end
  end
end
