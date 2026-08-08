# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    # ActiveRecord model classes that back the coordinator's SQLite tables.
    module Models
      # Row in the append-only `events` table, keyed by a UUID string.
      class EventRecord < ActiveRecord::Base
        self.table_name = "events"
        self.primary_key = "id"
      end
    end
  end
end
