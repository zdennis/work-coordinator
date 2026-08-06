# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      class EventRecord < ActiveRecord::Base
        self.table_name = "events"
        self.primary_key = "id"
      end
    end
  end
end
