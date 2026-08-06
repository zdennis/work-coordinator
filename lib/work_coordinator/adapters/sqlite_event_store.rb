# frozen_string_literal: true

require "securerandom"
require "json"
require "work_coordinator/domain/event"
require "work_coordinator/persistence/models/event_record"

module WorkCoordinator
  module Adapters
    class SqliteEventStore
      def append(type:, work_item_id:, source: "coordinator", data: {}, occurred_at: Time.now) # rubocop:disable Lint/UnusedMethodArgument
        record(type: type, work_item_id: work_item_id, source: source, data: data)
      end

      def record(type:, work_item_id:, source: "coordinator", data: {})
        record = Persistence::Models::EventRecord.create!(
          id: SecureRandom.uuid,
          work_item_id: work_item_id,
          event_type: type.to_s,
          source: source,
          data: JSON.generate(data),
          occurred_at: Time.now
        )
        to_domain(record)
      end

      def all_for(work_item_id:)
        Persistence::Models::EventRecord
          .where(work_item_id: work_item_id)
          .order(:occurred_at)
          .map { |r| to_domain(r) }
      end

      def last_of_type(type:, work_item_id:)
        record = Persistence::Models::EventRecord
                 .where(work_item_id: work_item_id, event_type: type.to_s)
                 .order(occurred_at: :desc)
                 .first
        record && to_domain(record)
      end

      private

      def to_domain(record)
        Domain::Event.new(
          id: record.id,
          work_item_id: record.work_item_id,
          type: record.event_type.to_sym,
          source: record.source,
          data: record.data ? JSON.parse(record.data) : {},
          occurred_at: record.occurred_at
        )
      end
    end
  end
end
