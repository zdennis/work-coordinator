# frozen_string_literal: true

module WorkCoordinator
  module Ports
    module MessageReceiver
      def receive_messages(since: nil) = raise NotImplementedError
      def on_message(&) = raise NotImplementedError
    end
  end
end
