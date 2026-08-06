# frozen_string_literal: true

class CreateResourceLeases < ActiveRecord::Migration[7.1]
  def change
    create_table :resource_leases, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.string :resource_name, null: false
      t.string :work_item_id, null: false
      t.datetime :acquired_at, null: false
      t.datetime :released_at
    end

    add_index :resource_leases, :resource_name
  end
end
