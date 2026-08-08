# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # In-memory receiver for tests. Messages are pushed in with
    # {#stub_message} and pulled out with {#receive_messages}; {#on_message}
    # does nothing.
    class FakeMessageReceiver
      include Ports::MessageReceiver

      def initialize
        @queue = []
      end

      # Queues a message as though it had just arrived.
      #
      # @param work_item_ref [String]
      # @param body [String]
      # @return [void]
      def stub_message(work_item_ref:, body:)
        @queue << { work_item_ref: work_item_ref, body: body, received_at: Time.now }
      end

      def receive_messages(since: nil)
        messages = @queue.dup
        messages = messages.select { |m| m[:received_at] > since } if since
        messages
      end

      def on_message(&)
        # no-op stub
      end
    end
  end
end
