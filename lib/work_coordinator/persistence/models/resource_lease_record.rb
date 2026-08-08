# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      # Row in `resource_leases`, keyed by a string id.
      class ResourceLeaseRecord < ActiveRecord::Base
        self.table_name = "resource_leases"
        self.primary_key = "id"

        # Unreleased leases on the named resource.
        # @param resource [String]
        scope :active_for, ->(resource) { where(resource_name: resource, released_at: nil) }
      end
    end
  end
end
