# frozen_string_literal: true

class CreateRestartStates < ActiveRecord::Migration[7.1]
  def change
    create_table :restart_states, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.integer :attempt, null: false, default: 0
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end
  end
end
