# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      class WorkItemRecord < ActiveRecord::Base
        self.table_name = "work_items"
        self.primary_key = "id"

        scope :with_state, ->(s) { where(state: s.to_s) }
      end
    end
  end
end
