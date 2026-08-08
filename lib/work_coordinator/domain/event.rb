# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # An append-only record of something that happened to a work item.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] work_item_id
    #   @return [String]
    # @!attribute [r] type
    #   @return [Symbol, String] dotted name such as `work_item.started`
    # @!attribute [r] source
    #   @return [String] who caused it — "system", "agent", or "human"
    # @!attribute [r] data
    #   @return [Hash] type-specific payload
    # @!attribute [r] occurred_at
    #   @return [Time]
    Event = Data.define(:id, :work_item_id, :type, :source, :data, :occurred_at)
  end
end
