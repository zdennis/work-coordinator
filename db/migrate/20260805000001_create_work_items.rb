# frozen_string_literal: true

class CreateWorkItems < ActiveRecord::Migration[7.1]
  def change
    create_table :work_items, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.string :title, null: false
      t.string :kind, null: false
      t.string :external_reference
      t.string :repository
      t.string :workspace_name
      t.string :tmux_target
      t.string :state, null: false, default: "created"
      t.string :phase
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :work_items, :external_reference
  end
end
