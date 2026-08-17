# frozen_string_literal: true

class AddPidToWorkspaceAgentRegistrations < ActiveRecord::Migration[7.1]
  def change
    add_column :workspace_agent_registrations, :pid, :integer
  end
end
