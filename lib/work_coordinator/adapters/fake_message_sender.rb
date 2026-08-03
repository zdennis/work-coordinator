# frozen_string_literal: true

require "work_coordinator/ports/message_sender"

module WorkCoordinator
  module Adapters
    class FakeMessageSender
      include Ports::MessageSender

      def initialize
        @sent_messages = []
      end

      def send_message(to:, body:, conversation_id: nil)
        @sent_messages << { to: to, body: body, conversation_id: conversation_id }
      end

      def sent_messages
        @sent_messages.dup
      end
    end
  end
end
