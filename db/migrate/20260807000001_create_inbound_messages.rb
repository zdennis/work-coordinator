# frozen_string_literal: true

class CreateInboundMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :inbound_messages do |t|
      t.string :guid, null: false
    end

    add_index :inbound_messages, :guid, unique: true
  end
end
