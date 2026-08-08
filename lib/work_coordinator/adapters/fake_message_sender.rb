# frozen_string_literal: true

require "work_coordinator/ports/message_sender"

module WorkCoordinator
  module Adapters
    # In-memory sender for tests; captures sends instead of transmitting them.
    class FakeMessageSender
      include Ports::MessageSender

      # @return [void]
      def initialize
        @sent_messages = []
      end

      # Records the send without transmitting; all parameters are captured.
      #
      # @param to [String]
      # @param body [String]
      # @param conversation_id [String, nil]
      # @return [void]
      def send_message(to:, body:, conversation_id: nil)
        @sent_messages << { to: to, body: body, conversation_id: conversation_id }
      end

      # @return [Array<Hash{Symbol=>String, nil}>] every send, as
      #   `{ to:, body:, conversation_id: }`, in order
      def sent_messages
        @sent_messages.dup
      end
    end
  end
end
