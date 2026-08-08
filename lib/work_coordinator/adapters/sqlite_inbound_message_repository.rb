# frozen_string_literal: true

require "work_coordinator/persistence/models/inbound_message_record"

module WorkCoordinator
  module Adapters
    class SqliteInboundMessageRepository
      def seen?(guid)
        Persistence::Models::InboundMessageRecord.exists?(guid: guid)
      end

      def record(guid)
        Persistence::Models::InboundMessageRecord.create!(guid: guid)
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end
  end
end
