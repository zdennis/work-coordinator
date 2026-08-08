# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      # Row in `work_items`, keyed by a UUID string.
      class WorkItemRecord < ActiveRecord::Base
        self.table_name = "work_items"
        self.primary_key = "id"

        # Work items in the given state, which may be a symbol or string.
        # @param s [Symbol, String]
        scope :with_state, ->(s) { where(state: s.to_s) }
      end
    end
  end
end
