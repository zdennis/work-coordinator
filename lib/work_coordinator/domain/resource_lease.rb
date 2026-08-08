# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # A work item's claim on a shared, capacity-limited resource.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] resource_name
    #   @return [String]
    # @!attribute [r] work_item_id
    #   @return [String] holder of the lease
    # @!attribute [r] acquired_at
    #   @return [Time]
    # @!attribute [r] released_at
    #   @return [Time, nil] nil while the lease is still held
    ResourceLease = Data.define(:id, :resource_name, :work_item_id, :acquired_at, :released_at) do
      # @return [Boolean]
      def released?
        !released_at.nil?
      end
    end
  end
end
