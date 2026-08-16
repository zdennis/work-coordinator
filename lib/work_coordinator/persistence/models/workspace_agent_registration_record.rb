# frozen_string_literal: true

module WorkCoordinator
  module Persistence
    module Models
      # Row in `workspace_agent_registrations`, one per live workspace agent.
      class WorkspaceAgentRegistrationRecord < ActiveRecord::Base
        self.table_name = "workspace_agent_registrations"
      end
    end
  end
end
