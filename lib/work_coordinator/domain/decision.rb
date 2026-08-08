# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # An architecture-decision-record style note captured against a work item.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] work_item_id
    #   @return [String]
    # @!attribute [r] title
    #   @return [String]
    # @!attribute [r] status
    #   @return [Symbol] :proposed, :accepted, :superseded, or :rejected
    # @!attribute [r] context
    #   @return [String, nil] the situation that forced the decision
    # @!attribute [r] decision_text
    #   @return [String, nil] what was decided
    # @!attribute [r] consequences
    #   @return [String, nil] what the decision commits the work to
    # @!attribute [r] source
    #   @return [String] who recorded it
    # @!attribute [r] created_at
    #   @return [Time]
    Decision = Data.define(:id, :work_item_id, :title, :status, :context, :decision_text, :consequences, :source,
                           :created_at) do
      # @return [Boolean]
      def proposed?   = status == :proposed
      # @return [Boolean]
      def accepted?   = status == :accepted
      # @return [Boolean]
      def superseded? = status == :superseded
      # @return [Boolean]
      def rejected?   = status == :rejected
    end
  end
end
