# frozen_string_literal: true

require "securerandom"
require "work_coordinator/domain/work_item"

module WorkCoordinator
  module Application
    # Creates a work item in the `created` state and records its birth event.
    class RegisterWorkItem
      # @param work_item_repo [Ports::WorkItemRepository]
      # @param event_store [#append]
      # @param project_repo [Ports::ProjectRepository, nil] used to auto-assign the default project
      # @return [void]
      def initialize(work_item_repo:, event_store:, project_repo: nil)
        @work_item_repo = work_item_repo
        @event_store    = event_store
        @project_repo   = project_repo
      end

      # @param title [String]
      # @param kind [Symbol] one of {Domain::WORK_ITEM_KINDS}
      # @param external_reference [String, nil] ticket key used to route replies
      # @param repository [String, nil]
      # @param workspace_name [String, nil] tmux target the agent will run in
      # @param project_id [String, nil] explicit project FK; defaults to the default project when nil
      # @param initial_state [Symbol] state the item starts in (default: `:created`)
      # @return [Domain::WorkItem] the persisted work item
      def call(title:, kind:, external_reference: nil, repository: nil, workspace_name: nil, project_id: nil,
               initial_state: :created)
        project_id ||= @project_repo&.default_project&.id
        work_item = build_work_item(title: title, kind: kind, external_reference: external_reference,
                                    repository: repository, workspace_name: workspace_name,
                                    project_id: project_id, initial_state: initial_state)
        @work_item_repo.save(work_item)
        record_created_event(work_item, title: title, kind: kind, external_reference: external_reference,
                                        project_id: project_id)
        work_item
      end

      private

      def build_work_item(title:, kind:, external_reference:, repository:, workspace_name:, project_id:,
                          initial_state: :created)
        now = Time.now
        Domain::WorkItem.new(
          id: SecureRandom.uuid,
          title: title,
          kind: kind,
          external_reference: external_reference,
          repository: repository,
          workspace_name: workspace_name,
          state: initial_state,
          phase: nil,
          project_id: project_id,
          created_at: now,
          updated_at: now
        )
      end

      def record_created_event(work_item, title:, kind:, external_reference:, project_id:)
        @event_store.append(
          type: "work_item.created",
          work_item_id: work_item.id,
          source: "system",
          data: { title: title, kind: kind, external_reference: external_reference, project_id: project_id }
        )
      end
    end
  end
end
