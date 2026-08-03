# frozen_string_literal: true

module WorkCoordinator
  module Domain
    ResourceLease = Data.define(:id, :resource_name, :work_item_id, :acquired_at, :released_at) do
      def released?
        !released_at.nil?
      end
    end
  end
end
