# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # A named project that groups work items and maps to a tmux workspace.
    # Immutable — transitions produce a new value via `with`.
    #
    # @!attribute [r] id
    #   @return [String] unique identifier (UUID)
    # @!attribute [r] name
    #   @return [String] human-readable project name
    # @!attribute [r] alias
    #   @return [String, nil] short abbreviation used for routing (e.g. "MS")
    # @!attribute [r] workspace_name
    #   @return [String, nil] tmux session name the project's agent runs in
    # @!attribute [r] is_default
    #   @return [Boolean] whether this is the active default project
    # @!attribute [r] created_at
    #   @return [Time] when the project was created
    # @!attribute [r] updated_at
    #   @return [Time] when the project was last modified
    Project = Data.define(
      :id,
      :name,
      :alias,
      :workspace_name,
      :is_default,
      :created_at,
      :updated_at
    )
  end
end
