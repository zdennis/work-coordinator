# frozen_string_literal: true

class CreateWorkspaceAgentRegistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :workspace_agent_registrations do |t|
      t.string :workspace_name, null: false
      t.string :socket_path, null: false
      t.boolean :pipeline, null: false, default: false
      t.string :epoch, null: false
      t.timestamps
    end

    add_index :workspace_agent_registrations, :workspace_name, unique: true
  end
end
