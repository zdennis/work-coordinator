# frozen_string_literal: true

module WorkCoordinator
  module Domain
    Event = Data.define(:id, :work_item_id, :type, :source, :data, :occurred_at)
  end
end
