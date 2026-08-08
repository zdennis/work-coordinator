# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Relays an agent's question to the human and parks the work item until
    # they answer.
    class NotifyHuman
      # @param message_sender [Ports::MessageSender]
      # @param work_item_repo [Ports::WorkItemRepository]
      # @param event_store [#append]
      # @return [void]
      def initialize(message_sender:, work_item_repo:, event_store:)
        @message_sender = message_sender
        @work_item_repo = work_item_repo
        @event_store = event_store
      end

      # Sends the body prefixed with the work item's external reference so the
      # reply can be routed back, moves the item to `waiting_for_human`, and
      # records an `agent.question_asked` event.
      #
      # @param work_item_id [String]
      # @param body [String] the question to ask
      # @return [Domain::WorkItem] the item in its waiting state
      # @raise [RuntimeError] when no work item matches the id
      def call(work_item_id:, body:)
        work_item = @work_item_repo.find(work_item_id)
        raise "work item not found: #{work_item_id}" unless work_item

        ref = work_item.external_reference
        formatted = "[#{ref}] #{body}\nReply: #{ref} <your response>"

        @message_sender.send_message(to: nil, body: formatted)

        waiting_item = work_item.with(state: :waiting_for_human, updated_at: Time.now)
        @work_item_repo.save(waiting_item)

        record_events(work_item_id: work_item_id, ref: ref, body: body)

        waiting_item
      end

      private

      def record_events(work_item_id:, ref:, body:)
        @event_store.append(
          type: "agent.question_asked",
          work_item_id: work_item_id,
          source: "agent",
          data: { body: body }
        )
        @event_store.append(
          type: "system.notified",
          work_item_id: work_item_id,
          source: "system",
          data: { ref: ref, body: body }
        )
      end
    end
  end
end
