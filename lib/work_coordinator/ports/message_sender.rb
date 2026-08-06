# frozen_string_literal: true

module WorkCoordinator
  module Ports
    module MessageSender
      def send_message(to:, body:, conversation_id: nil) = raise NotImplementedError
    end
  end
end
