# frozen_string_literal: true

require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Application
    # Delivers instructions to the main agent pane of a named workspace session.
    #
    # Used by the `claude` and `main` verb routing paths in AiCommandReceiver.
    # Sends an acknowledgment back to the recipient on success; sends the error
    # message on failure.
    #
    # The recipient is passed through to message_sender. A nil recipient routes
    # to the default WC_RECIPIENT configured in AppleScriptMessageSender.
    #
    # Pane numbering: domain pane indices are 1-based. TmuxAgentSession converts
    # them to 0-based tmux indices (domain 1 → tmux 0, domain 2 → tmux 1, etc.).
    # MAIN_PANE_INDEX = 2 therefore targets tmux pane index 1.
    class DeliverToMainSession
      # @!attribute [r] success [Boolean]
      # @!attribute [r] error [String, nil]
      Result = Data.define(:success, :error)

      # Domain pane index 2 = tmux pane index 1 (the main agent pane).
      # Pane 0 (domain 1) is reserved for the banner/status program.
      MAIN_PANE_INDEX = 2

      # @param agent_session [Ports::AgentSession]
      # @param message_sender [Ports::MessageSender]
      # @param aliases [Hash] short-name => project-name alias map (case-insensitive lookup)
      def initialize(agent_session:, message_sender:, aliases: {})
        @agent_session  = agent_session
        @message_sender = message_sender
        @aliases        = aliases
      end

      # @param workspace_name [String] name (or alias) of the tmux session to target
      # @param instructions [String] text to deliver to the pane
      # @param recipient [String, nil] address to ack; nil uses the default WC_RECIPIENT
      # @return [Result]
      def call(workspace_name:, instructions:, recipient:)
        resolved = @aliases[workspace_name.strip.upcase] || workspace_name
        @agent_session.deliver_to_pane(
          workspace_name: resolved,
          pane_index: MAIN_PANE_INDEX,
          message: instructions
        )
        summary = instructions.length > 80 ? "#{instructions[0, 80]}..." : instructions
        @message_sender.send_message(to: recipient, body: "Sent to #{resolved}: #{summary}")
        Result.new(success: true, error: nil)
      rescue StandardError => e
        @message_sender.send_message(to: recipient, body: "Error: #{e.message}")
        Result.new(success: false, error: e.message)
      end
    end
  end
end
