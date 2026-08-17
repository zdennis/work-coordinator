# frozen_string_literal: true

require "socket"
require "work_coordinator/ports/message_sender"

module WorkCoordinator
  module Adapters
    # Writes messages as newline-terminated lines to a Unix domain socket, the
    # counterpart to {SocketMessageReceiver}.
    class SocketMessageSender
      include Ports::MessageSender

      # @param socket_path [String]
      def initialize(socket_path: Paths.socket)
        @socket_path = socket_path
      end

      # The socket has a single reader, so `to` is ignored.
      #
      # @param body [String]
      # @param to [String, nil] ignored
      # @param work_item_id [String, nil] ignored
      # @return [void]
      def send_message(body:, to: nil, work_item_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        UNIXSocket.open(@socket_path) do |sock|
          sock.puts(body)
        end
      end
    end
  end
end
