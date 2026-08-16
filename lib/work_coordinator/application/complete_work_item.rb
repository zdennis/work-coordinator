# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Finishes a work item and tells the human it is done, without asking for a
    # reply the way {NotifyHuman} does.
    class CompleteWorkItem
      # @param message_sender [Ports::MessageSender]
      # @param work_item_repo [Ports::WorkItemRepository]
      # @param event_store [#append]
      def initialize(message_sender:, work_item_repo:, event_store:)
        @message_sender = message_sender
        @work_item_repo = work_item_repo
        @event_store = event_store
      end

      # Moves the item to `completed`, sends the summary prefixed with the
      # external reference, and records an `agent.work_completed` event. Calling
      # it again on an item that already reached a terminal state is a no-op, so
      # a duplicate completion signal is acknowledged rather than re-announced.
      #
      # @param work_item_id [String]
      # @param summary [String] what was accomplished
      # @return [Domain::WorkItem] the completed item
      # @raise [RuntimeError] when no work item matches the id
      def call(work_item_id:, summary:)
        work_item = @work_item_repo.find(work_item_id)
        raise "work item not found: #{work_item_id}" unless work_item
        return work_item if work_item.terminal?

        completed = work_item.transition_to(:completed).with(updated_at: Time.now)
        @work_item_repo.save(completed)

        @message_sender.send_message(to: nil, body: "[#{completed.external_reference}] Done — #{summary}")

        @event_store.append(
          type: "agent.work_completed",
          work_item_id: work_item_id,
          source: "agent",
          data: { summary: summary }
        )

        completed
      end
    end
  end
end
