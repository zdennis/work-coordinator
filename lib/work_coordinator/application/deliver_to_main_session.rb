# frozen_string_literal: true

require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Application
    # Delivers instructions to pane 1 (the main agent pane) of a named workspace session.
    #
    # Used by the `claude` and `main` verb routing paths in AiCommandReceiver.
    # Sends an acknowledgment back to the recipient on success; sends the error
    # message on failure.
    #
    # The recipient is passed through to message_sender. A nil recipient routes
    # to the default WC_RECIPIENT configured in AppleScriptMessageSender.
    class DeliverToMainSession
      # @!attribute [r] success [Boolean]
      # @!attribute [r] error [String, nil]
      Result = Data.define(:success, :error)

      MAIN_PANE_INDEX = 1

      # @param agent_session [Ports::AgentSession]
      # @param message_sender [Ports::MessageSender]
      def initialize(agent_session:, message_sender:)
        @agent_session  = agent_session
        @message_sender = message_sender
      end

      # @param workspace_name [String] name of the tmux session to target
      # @param instructions [String] text to deliver to the pane
      # @param recipient [String, nil] address to ack; nil uses the default WC_RECIPIENT
      # @return [Result]
      def call(workspace_name:, instructions:, recipient:)
        @agent_session.deliver_to_pane(
          workspace_name: workspace_name,
          pane_index: MAIN_PANE_INDEX,
          message: instructions
        )
        @message_sender.send_message(to: recipient, body: "Sent to #{workspace_name}")
        Result.new(success: true, error: nil)
      rescue StandardError => e
        @message_sender.send_message(to: recipient, body: "Error: #{e.message}")
        Result.new(success: false, error: e.message)
      end
    end
  end
end
