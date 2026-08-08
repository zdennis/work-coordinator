# frozen_string_literal: true

require "work_coordinator/persistence/models/inbound_message_record"

module WorkCoordinator
  module Adapters
    # Remembers which inbound message guids have been handled, so a restarted
    # poller does not re-deliver messages it already processed.
    class SqliteInboundMessageRepository
      # @param guid [String]
      # @return [Boolean]
      def seen?(guid)
        Persistence::Models::InboundMessageRecord.exists?(guid: guid)
      end

      # Marks the guid handled. Recording the same guid twice is a no-op.
      #
      # @param guid [String]
      # @return [Persistence::Models::InboundMessageRecord, nil]
      def record(guid)
        Persistence::Models::InboundMessageRecord.create!(guid: guid)
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
