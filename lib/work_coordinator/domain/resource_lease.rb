# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # A work item's claim on a shared, capacity-limited resource.
    #
    # @!attribute [r] id
    #   @return [String] unique identifier for this lease
    # @!attribute [r] resource_name
    #   @return [String] name of the resource being held
    # @!attribute [r] work_item_id
    #   @return [String] holder of the lease
    # @!attribute [r] acquired_at
    #   @return [Time] when the lease was granted
    # @!attribute [r] released_at
    #   @return [Time, nil] when the lease was released, or nil while still held
    ResourceLease = Data.define(:id, :resource_name, :work_item_id, :acquired_at, :released_at) do
      # Returns true when the lease has been returned.
      # @return [Boolean]
      def released?
        !released_at.nil?
      end
    end
  end
end
