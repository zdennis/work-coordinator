module WorkCoordinator
  module Ports
    module MessageReceiver
      def receive_messages(since: nil) = raise NotImplementedError
      def on_message(&block) = raise NotImplementedError
    end
  end
end
