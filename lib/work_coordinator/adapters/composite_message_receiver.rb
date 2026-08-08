# frozen_string_literal: true

require "work_coordinator/ports/message_receiver"

module WorkCoordinator
  module Adapters
    # Runs several message receivers concurrently, serializing delivery to the
    # caller's block so handlers never run in parallel.
    class CompositeMessageReceiver
      include Ports::MessageReceiver

      def initialize(receivers)
        @receivers = receivers
        @threads = []
      end

      def start(&block)
        mutex = Mutex.new
        safe_block = ->(message) { mutex.synchronize { block.call(message) } }
        @threads = @receivers.map { |receiver| Thread.new { receiver.start(&safe_block) } }
        @threads.each(&:join)
      rescue StandardError
        stop
        raise
      end

      def stop
        @receivers.each(&:stop)
      end
    end
  end
end
