# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Tells the human something about a work item without asking them for
    # anything. Unlike {NotifyHuman} it sends no reply hint and makes no state
    # transition — the agent is still in charge of the item.
    class InformHuman
      # @param message_sender [Ports::MessageSender]
      # @param event_store [#append]
      def initialize(message_sender:, event_store:)
        @message_sender = message_sender
        @event_store = event_store
      end

      # @param work_item_id [String]
      # @param body [String]
      # @param work_item [Domain::WorkItem] the item, already in hand from the caller
      # @return [Domain::WorkItem] unchanged
      def call(work_item_id:, body:, work_item:)
        ref = work_item.external_reference
        @message_sender.send_message(to: nil, body: "[#{ref}] #{body}")
        @event_store.append(
          type: "system.informed",
          work_item_id: work_item_id,
          source: "system",
          data: { ref: ref, body: body }
        )
        work_item
      end
    end
  end
end
