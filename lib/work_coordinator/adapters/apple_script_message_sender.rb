# frozen_string_literal: true

require "open3"
require "work_coordinator/ports/message_sender"

module WorkCoordinator
  module Adapters
    # Sends messages through macOS Messages by shelling out to a `send-message`
    # helper, which drives Messages.app via AppleScript.
    class AppleScriptMessageSender
      include Ports::MessageSender

      # @param send_message_bin [String] path to (or name of) the helper binary
      def initialize(send_message_bin: "send-message")
        @send_message_bin = send_message_bin
      end

      # The recipient is configured in the helper, so `to` is ignored.
      #
      # @param body [String]
      # @param to [String, nil] ignored
      # @param work_item_id [String, nil] ignored
      # @return [void]
      # @raise [RuntimeError] when the helper exits non-zero
      def send_message(body:, to: nil, work_item_id: nil, conversation_id: nil) # rubocop:disable Lint/UnusedMethodArgument
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
