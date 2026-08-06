# frozen_string_literal: true

class RemoveTmuxTargetFromWorkItems < ActiveRecord::Migration[7.1]
  def change
    remove_column :work_items, :tmux_target, :string
  end
end
