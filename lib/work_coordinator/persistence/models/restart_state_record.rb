# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      # The single row in `restart_states`, always keyed "coordinator".
      # It exists only while a restart is in flight.
      class RestartStateRecord < ActiveRecord::Base
        self.table_name  = "restart_states"
        self.primary_key = "id"

        SINGLETON_ID = "coordinator"
      end
    end
  end
end
