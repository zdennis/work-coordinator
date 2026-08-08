# frozen_string_literal: true

require "work_coordinator/domain/event"

module WorkCoordinator
  module Application
    # Non-persistent event store for tests and dry runs. Ids are sequential
    # integers rendered as strings.
    class InMemoryEventStore
      # @return [void]
      def initialize
        @events = []
        @next_id = 0
      end

      # @param type [Symbol, String]
      # @param work_item_id [String]
      # @param source [String]
      # @param data [Hash]
      # @param occurred_at [Time]
      # @return [Domain::Event] the appended event
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

      # @return [Array<Domain::Event>] every event, in append order
      def all
        @events.dup
      end
    end
  end
end
