# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      class ResourceLeaseRecord < ActiveRecord::Base
        self.table_name = "resource_leases"
        self.primary_key = "id"

        scope :active_for, ->(resource) { where(resource_name: resource, released_at: nil) }
      end
    end
  end
end
