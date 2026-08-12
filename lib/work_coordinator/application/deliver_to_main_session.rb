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
      # @param instruction_context [String] text appended to every instruction before delivery
      # @param project_repo [Ports::ProjectRepository, nil] used for DB-backed alias resolution
      def initialize(agent_session:, message_sender:, aliases: {}, instruction_context: "",
                     project_repo: nil)
        @agent_session       = agent_session
        @message_sender      = message_sender
        @aliases             = aliases
        @instruction_context = instruction_context
        @project_repo        = project_repo
      end

      # @param workspace_name [String] name (or alias) of the tmux session to target
      # @param instructions [String] text to deliver to the pane
      # @param recipient [String, nil] address to ack; nil uses the default WC_RECIPIENT
      # @return [Result]
      def call(workspace_name:, instructions:, recipient:)
        resolved = resolve_alias(workspace_name)
        full_message = build_message(instructions)
        @agent_session.deliver_to_pane(
          workspace_name: resolved,
          pane_index: MAIN_PANE_INDEX,
          message: full_message
        )
        summary = instructions.length > 80 ? "#{instructions[0, 80]}..." : instructions
        @message_sender.send_message(to: recipient, body: "Sent to #{resolved}: #{summary}")
        Result.new(success: true, error: nil)
      rescue StandardError => e
        @message_sender.send_message(to: recipient, body: "Error: #{e.message}")
        Result.new(success: false, error: e.message)
      end

      private

      def resolve_alias(workspace_name)
        key = workspace_name.strip.upcase
        if @project_repo
          project = @project_repo.find_by_name_or_alias(key) ||
                    @project_repo.find_by_name_or_alias(workspace_name.strip)
          return project.workspace_name if project&.workspace_name
        end
        @aliases[key] || workspace_name
      end

      def build_message(instructions)
        normalized = normalize_slash_separator(instructions)
        return normalized if @instruction_context.nil? || @instruction_context.strip.empty?

        "#{normalized}\n\n#{@instruction_context}"
      end

      # When instructions begin with a slash command immediately followed by content
      # (space/tab or single newline), normalize to \n\n so the command and any
      # trailing context are always separated by a blank line.
      def normalize_slash_separator(instructions)
        instructions.sub(%r{\A(/\w+)(?:[ \t]+|\n(?!\n))}, "\\1\n\n")
      end
    end
  end
end
