# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :events, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.string :work_item_id, null: false
      t.string :event_type, null: false
      t.string :source
      t.text :data
      t.datetime :occurred_at, null: false
    end

    add_index :events, %i[work_item_id event_type]
  end
end
