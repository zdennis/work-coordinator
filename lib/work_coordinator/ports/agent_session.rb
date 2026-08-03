# frozen_string_literal: true

module WorkCoordinator
  module Ports
    module AgentSession
      def start_session(work_item_id:) = raise NotImplementedError
      def deliver(session_id:, message:) = raise NotImplementedError
      def end_session(session_id:) = raise NotImplementedError
      def active_session(work_item_id:) = raise NotImplementedError
    end
  end
end
