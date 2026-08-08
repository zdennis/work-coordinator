# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # An architecture-decision-record style note captured against a work item.
    #
    # @!attribute [r] id
    #   @return [String] unique identifier for this decision
    # @!attribute [r] work_item_id
    #   @return [String] ID of the work item this decision is associated with
    # @!attribute [r] title
    #   @return [String] short name summarising what was decided
    # @!attribute [r] status
    #   @return [Symbol] :proposed, :accepted, :superseded, or :rejected
    # @!attribute [r] context
    #   @return [String, nil] the situation that forced the decision
    # @!attribute [r] decision_text
    #   @return [String, nil] what was decided
    # @!attribute [r] consequences
    #   @return [String, nil] what the decision commits the work to
    # @!attribute [r] source
    #   @return [String] who recorded it — "system", "agent", or "human"
    # @!attribute [r] created_at
    #   @return [Time] when the decision was recorded
    Decision = Data.define(:id, :work_item_id, :title, :status, :context, :decision_text, :consequences, :source,
                           :created_at) do
      # Returns true when the decision is still under consideration.
      # @return [Boolean]
      def proposed?   = status == :proposed

      # Returns true when the decision has been formally accepted.
      # @return [Boolean]
      def accepted?   = status == :accepted

      # Returns true when the decision has been replaced by a newer one.
      # @return [Boolean]
      def superseded? = status == :superseded

      # Returns true when the decision was considered but turned down.
      # @return [Boolean]
      def rejected?   = status == :rejected
    end
  end
end
