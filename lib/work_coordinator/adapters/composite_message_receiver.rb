# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # Runs several message receivers concurrently. Each message is dispatched
    # on its own thread so a slow handler (tmux subprocess, AppleScript, etc.)
    # does not block delivery of subsequent messages.
    class CompositeMessageReceiver
      include Ports::MessageReceiver

      # @param receivers [Array<#start, #stop>]
      def initialize(receivers)
        @receivers = receivers
        @threads = []
      end

      # Starts every receiver on its own thread and blocks until they all
      # finish. Each incoming message is handled on a dedicated thread so
      # handlers run in parallel — one slow message does not delay the next.
      #
      # If any receiver thread raises, the remaining receivers are stopped and
      # the error propagates.
      #
      # @yieldparam message [Hash]
      # @return [void]
      DRAIN_SENTINEL = Object.new.freeze
      private_constant :DRAIN_SENTINEL

      def start(&block)
        handler_threads = Queue.new
        dispatch = ->(message) { handler_threads << Thread.new { block.call(message) } }
        @threads = @receivers.map { |receiver| Thread.new { receiver.start(&dispatch) } }
        @threads.each(&:join)
        # Signal that no more items will be enqueued, then join all handlers.
        handler_threads << DRAIN_SENTINEL
        drain_handlers(handler_threads)
      rescue StandardError
        stop
        handler_threads << DRAIN_SENTINEL
        drain_handlers(handler_threads)
        raise
      end

      # Stops every wrapped receiver, unblocking {#start}.
      #
      # @return [void]
      def stop
        @receivers.each(&:stop)
      end

      private

      def drain_handlers(queue)
        pending = []
        loop do
          item = queue.pop
          break if item.equal?(DRAIN_SENTINEL)

          pending << item
        end
        pending.each(&:join)
      end
    end
  end
end
