module WorkCoordinator
  module Domain
    WorkItem = Data.define(
      :id,
      :title,
      :kind,
      :external_reference,
      :repository,
      :workspace_name,
      :state,
      :phase,
      :created_at,
      :updated_at
    ) do
      STATES = %i[created ready active waiting_for_human waiting_for_resource blocked completed abandoned].freeze
      KINDS = %i[jira chore investigation adhoc].freeze
      PHASES = %i[investigating implementing verifying reviewing].freeze

      def state?(s) = state == s

      def created?           = state?(:created)
      def ready?             = state?(:ready)
      def active?            = state?(:active)
      def waiting_for_human? = state?(:waiting_for_human)
      def waiting_for_resource? = state?(:waiting_for_resource)
      def blocked?           = state?(:blocked)
      def completed?         = state?(:completed)
      def abandoned?         = state?(:abandoned)

      # Compatibility aliases
      def open?        = created?
      def done?        = completed?
      def in_progress? = active?
    end
  end
end
