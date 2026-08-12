# frozen_string_literal: true

class AddProjectIdToWorkItems < ActiveRecord::Migration[7.1]
  def change
    add_column :work_items, :project_id, :string
    add_index  :work_items, :project_id
  end
end
