# frozen_string_literal: true

class CreateProjects < ActiveRecord::Migration[7.1]
  def change
    create_table :projects, id: false do |t|
      t.string :id, primary_key: true, null: false
      t.string :name, null: false
      t.string :alias
      t.string :workspace_name
      t.boolean :is_default, null: false, default: false
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
    end

    add_index :projects, :alias, unique: true
    add_index :projects, :name
  end
end
