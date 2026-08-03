# frozen_string_literal: true

module WorkCoordinator
  module Application
    class NotifyHuman
      def initialize(message_sender:, work_item_repo:, event_store:)
        @message_sender = message_sender
        @work_item_repo = work_item_repo
        @event_store = event_store
      end

      def call(work_item_id:, body:)
        work_item = @work_item_repo.find(work_item_id)
        raise "work item not found: #{work_item_id}" unless work_item

        ref = work_item.external_reference
        formatted = "[#{ref}] #{body}\nReply: #{ref} <your response>"

        @message_sender.send_message(to: nil, body: formatted)

        waiting_item = work_item.with(state: :waiting_for_human, updated_at: Time.now)
        @work_item_repo.save(waiting_item)

        @event_store.append(
          type: "agent.question_asked",
          work_item_id: work_item_id,
          source: "agent",
          data: { body: body }
        )

        waiting_item
      end
    end
  end
end
