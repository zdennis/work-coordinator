# frozen_string_literal: true

module WorkCoordinator
  module Domain
    WORK_ITEM_STATES = %i[created ready active waiting_for_human waiting_for_resource blocked completed
                          abandoned].freeze
    WORK_ITEM_KINDS = %i[jira chore investigation adhoc].freeze
    WORK_ITEM_PHASES = %i[investigating implementing verifying reviewing].freeze

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
      def state?(check_state) = state == check_state

      def created?              = state?(:created)
      def ready?                = state?(:ready)
      def active?               = state?(:active)
      def waiting_for_human?    = state?(:waiting_for_human)
      def waiting_for_resource? = state?(:waiting_for_resource)
      def blocked?              = state?(:blocked)
      def completed?            = state?(:completed)
      def abandoned?            = state?(:abandoned)

      def open?        = created?
      def done?        = completed?
      def in_progress? = active?
    end
  end
end
