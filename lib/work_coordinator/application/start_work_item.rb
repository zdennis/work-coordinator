# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Activates a work item and opens the agent session that will work on it.
    class StartWorkItem
      # @param work_item_repo [Ports::WorkItemRepository]
      # @param agent_session [Ports::AgentSession]
      # @param event_store [#append]
      def initialize(work_item_repo:, agent_session:, event_store:)
        @work_item_repo = work_item_repo
        @agent_session = agent_session
        @event_store = event_store
      end

      # @param work_item_id [String]
      # @return [Domain::WorkItem] the item in its active state
      # @raise [RuntimeError] when no work item matches the id
      def call(work_item_id:)
        work_item = @work_item_repo.find(work_item_id)
        raise "work item not found: #{work_item_id}" unless work_item

        active_item = work_item.with(state: :active, updated_at: Time.now)
        @work_item_repo.save(active_item)
        @agent_session.start_session(work_item_id: work_item_id)
        @event_store.append(
          type: "work_item.started",
          work_item_id: work_item_id,
          source: "system",
          data: {}
        )
        active_item
      end
    end
  end
end
