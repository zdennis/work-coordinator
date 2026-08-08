# frozen_string_literal: true

require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Adapters
    # In-memory agent session for tests. Sessions are named `session-N` and
    # delivered messages are captured rather than sent anywhere.
    class FakeAgentSession
      include Ports::AgentSession

      def initialize
        @sessions = {}        # session_id => work_item_id
        @active = {}          # work_item_id => session_id
        @messages = []
        @next_id = 0
      end

      def start_session(work_item_id:)
        session_id = "session-#{@next_id += 1}"
        @sessions[session_id] = work_item_id
        @active[work_item_id] = session_id
        session_id
      end

      def deliver(session_id:, message:)
        @messages << { session_id: session_id, message: message }
      end

      def end_session(session_id:)
        work_item_id = @sessions.delete(session_id)
        @active.delete(work_item_id) if work_item_id
      end

      def active_session(work_item_id:)
        @active[work_item_id]
      end

      # @return [Array<Hash{Symbol=>String}>] every delivery, as
      #   `{ session_id:, message: }`, in order
      def delivered_messages
        @messages.dup
      end
    end
  end
end
