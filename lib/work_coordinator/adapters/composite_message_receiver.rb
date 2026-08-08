# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # Runs several message receivers concurrently, serializing delivery to the
    # caller's block so handlers never run in parallel.
    class CompositeMessageReceiver
      include Ports::MessageReceiver

      # @param receivers [Array<#start, #stop>]
      def initialize(receivers)
        @receivers = receivers
        @threads = []
      end

      # Starts every receiver on its own thread and blocks until they all
      # finish. If any thread raises, the remaining receivers are stopped and
      # the error propagates.
      #
      # @yieldparam message [Hash]
      # @return [void]
      def start(&block)
        mutex = Mutex.new
        safe_block = ->(message) { mutex.synchronize { block.call(message) } }
        @threads = @receivers.map { |receiver| Thread.new { receiver.start(&safe_block) } }
        @threads.each(&:join)
      rescue StandardError
        stop
        raise
      end

      # Stops every wrapped receiver, unblocking {#start}.
      #
      # @return [void]
      def stop
        @receivers.each(&:stop)
      end
    end
  end
end
