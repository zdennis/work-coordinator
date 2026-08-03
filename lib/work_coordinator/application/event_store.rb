# frozen_string_literal: true

require "work_coordinator/domain/event"

module WorkCoordinator
  module Application
    class InMemoryEventStore
      def initialize
        @events = []
        @next_id = 0
      end

      def append(type:, work_item_id:, source:, data: {}, occurred_at: Time.now)
        event = Domain::Event.new(
          id: (@next_id += 1).to_s,
          work_item_id: work_item_id,
          type: type,
          source: source,
          data: data,
          occurred_at: occurred_at
        )
        @events << event
        event
      end

      def all
        @events.dup
      end
    end
  end
end
