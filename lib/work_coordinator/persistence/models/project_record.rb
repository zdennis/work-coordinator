# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      # Row in `projects`, keyed by a UUID string.
      class ProjectRecord < ActiveRecord::Base
        self.table_name  = "projects"
        self.primary_key = "id"

        # Returns the project flagged as the default, or nil when none is set.
        # Implemented as a class method (not a scope) because AR scopes that
        # return nil fall back to the `all` relation rather than nil itself.
        def self.default_project
          find_by(is_default: true)
        end
      end
    end
  end
end
