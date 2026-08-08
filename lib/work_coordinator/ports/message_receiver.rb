# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for inbound message transports.
    #
    # Implementors deliver message hashes shaped as
    # `{ work_item_ref:, body:, received_at: }`. Long-running receivers expose
    # `start(&block)` and `stop` instead of the pull-style methods below; a
    # given adapter typically implements one style and raises for the other.
    module MessageReceiver
      # Pulls messages that arrived after the given time.
      #
      # @param since [Time, nil] only return messages newer than this
      # @return [Array<Hash>]
      def receive_messages(since: nil) = raise NotImplementedError

      # Registers a callback invoked once per inbound message.
      #
      # @yieldparam message [Hash]
      # @return [void]
      def on_message(&) = raise NotImplementedError
    end
  end
end
