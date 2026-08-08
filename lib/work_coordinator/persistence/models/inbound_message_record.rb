# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      # Row in `inbound_messages`, recording the guid of a handled message so it
      # is never processed twice. Untimestamped.
      class InboundMessageRecord < ActiveRecord::Base
        self.table_name = "inbound_messages"
        self.record_timestamps = false
      end
    end
  end
end
