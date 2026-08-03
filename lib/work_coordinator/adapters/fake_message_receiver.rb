# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    class FakeMessageReceiver
      include Ports::MessageReceiver

      def initialize
        @queue = []
      end

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
