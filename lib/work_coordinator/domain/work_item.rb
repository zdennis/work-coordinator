# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Every state a work item may occupy.
    # @return [Array<Symbol>]
    WORK_ITEM_STATES = %i[created ready active waiting_for_human waiting_for_resource blocked completed
                          abandoned].freeze
    # Categories of work the coordinator tracks.
    # @return [Array<Symbol>]
    WORK_ITEM_KINDS = %i[jira chore investigation adhoc].freeze
    # Stages an active work item moves through.
    # @return [Array<Symbol>]
    WORK_ITEM_PHASES = %i[investigating implementing verifying reviewing].freeze

    # A single unit of tracked work, immutable — transitions produce a new value
    # via `with`.
    #
    # @!attribute [r] id
    #   @return [String] unique identifier for this work item
    # @!attribute [r] title
    #   @return [String] human-readable summary of the work
    # @!attribute [r] kind
    #   @return [Symbol] one of {WORK_ITEM_KINDS}
    # @!attribute [r] external_reference
    #   @return [String, nil] ticket key used as the message routing prefix
    # @!attribute [r] repository
    #   @return [String, nil] source-code repository the work targets
    # @!attribute [r] workspace_name
    #   @return [String, nil] tmux target the agent session runs in
    # @!attribute [r] state
    #   @return [Symbol] one of {WORK_ITEM_STATES}
    # @!attribute [r] phase
    #   @return [Symbol, nil] one of {WORK_ITEM_PHASES}, set only while the item is active
    # @!attribute [r] project_id
    #   @return [String, nil] FK to the owning project (nullable)
    # @!attribute [r] created_at
    #   @return [Time] when the work item was registered
    # @!attribute [r] updated_at
    #   @return [Time] when the work item was last modified
    WorkItem = Data.define(
      :id,
      :title,
      :kind,
      :external_reference,
      :repository,
      :workspace_name,
      :state,
      :phase,
      :project_id,
      :created_at,
      :updated_at
    ) do
      # Returns true when the work item's current state matches the given symbol.
      # @param check_state [Symbol] state to test against
      # @return [Boolean]
      def state?(check_state) = state == check_state

      # Returns true when the item has been registered but not yet started.
      # @return [Boolean]
      def created?              = state?(:created)

      # Returns true when the item is ready to be picked up by an agent.
      # @return [Boolean]
      def ready?                = state?(:ready)

      # Returns true when an agent is actively working on the item.
      # @return [Boolean]
      def active?               = state?(:active)

      # Returns true when the item is paused awaiting human input.
      # @return [Boolean]
      def waiting_for_human?    = state?(:waiting_for_human)

      # Returns true when the item is paused awaiting a resource to become available.
      # @return [Boolean]
      def waiting_for_resource? = state?(:waiting_for_resource)

      # Returns true when forward progress is externally prevented.
      # @return [Boolean]
      def blocked?              = state?(:blocked)

      # Returns true when the item has been successfully finished.
      # @return [Boolean]
      def completed?            = state?(:completed)

      # Returns true when the item was cancelled before completion.
      # @return [Boolean]
      def abandoned?            = state?(:abandoned)

      # Alias for {#created?} — registered but not yet started.
      # @return [Boolean]
      def open?        = created?

      # Alias for {#completed?} — the item reached a successful end state.
      # @return [Boolean]
      def done?        = completed?

      # Alias for {#active?} — an agent is currently working on the item.
      # @return [Boolean]
      def in_progress? = active?
    end
  end
end
