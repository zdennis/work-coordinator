# frozen_string_literal: true

require "socket"
require "work_coordinator/ports/message_sender"

module WorkCoordinator
  module Adapters
    class SocketMessageSender
      include Ports::MessageSender

      def initialize(socket_path: "/tmp/work-coordinator.sock")
        @socket_path = socket_path
      end

      def send_message(body:, to: nil, work_item_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        UNIXSocket.open(@socket_path) do |sock|
          sock.puts(body)
        end
      end
    end
  end
end
