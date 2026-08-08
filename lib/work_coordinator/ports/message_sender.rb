# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for outbound message transports.
    #
    # Implementors deliver the body to the human operator and raise when the
    # underlying transport reports failure.
    module MessageSender
      # @param to [String, nil] recipient, or nil to use the transport's default
      # @param body [String]
      # @param conversation_id [String, nil] thread to reply within, when supported
      # @return [void]
      def send_message(to:, body:, conversation_id: nil) = raise NotImplementedError
    end
  end
end
