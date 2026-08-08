# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      class InboundMessageRecord < ActiveRecord::Base
        self.table_name = "inbound_messages"
        self.record_timestamps = false
      end
    end
  end
end
