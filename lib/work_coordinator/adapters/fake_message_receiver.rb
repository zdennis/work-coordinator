# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # In-memory receiver for tests. Messages are pushed in with
    # {#stub_message} and pulled out with {#receive_messages}; {#on_message}
    # does nothing.
    class FakeMessageReceiver
      include Ports::MessageReceiver

      # @return [void]
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

      # Returns all queued messages, optionally filtered to those received after
      # the given time.
      #
      # @param since [Time, nil]
      # @return [Array<Hash{Symbol=>String, Time}>]
      def receive_messages(since: nil)
        messages = @queue.dup
        messages = messages.select { |m| m[:received_at] > since } if since
        messages
      end

      # No-op; push-style callbacks are not supported by this fake.
      #
      # @return [void]
      def on_message(&)
        # no-op stub
      end

      # Drains the queue through the block, standing in for a long-running
      # receiver so adapters that wrap one can be driven in tests.
      #
      # @yieldparam message [Hash{Symbol=>String, Time}]
      # @return [void]
      def start(&)
        @queue.each(&)
      end

      # Marks the receiver stopped; there is nothing to tear down.
      #
      # @return [void]
      def stop
        @stopped = true
      end

      # @return [Boolean]
      def stopped? = @stopped == true
    end
  end
end
