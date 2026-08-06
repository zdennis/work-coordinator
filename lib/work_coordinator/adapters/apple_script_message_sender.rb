# frozen_string_literal: true

require "open3"
require "work_coordinator/ports/message_sender"

module WorkCoordinator
  module Adapters
    class AppleScriptMessageSender
      include Ports::MessageSender

      def initialize(send_message_bin: "send-message")
        @send_message_bin = send_message_bin
      end

      def send_message(body:, to: nil, work_item_id: nil) # rubocop:disable Lint/UnusedMethodArgument
        cmd = [@send_message_bin, "--message", body]
        output, status = run_command(cmd)
        raise "send-message failed: #{output}" unless status.success?
      end

      protected

      def run_command(cmd)
        Open3.capture2e(*cmd)
      end
    end
  end
end
