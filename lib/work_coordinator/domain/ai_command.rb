# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Parses the body of an ai: message into its verb, workspace, and instructions.
    #
    # Recognized format:  [VERB] WORKSPACE - instructions
    # VERB is optional; when absent the whole body falls through to DispatchAiCommand.
    #
    # @example
    #   AiCommand.new("claude GE - add validation").send_to_main_session?  # => true
    #   AiCommand.new("GE - add validation").send_to_main_session?          # => false
    #   AiCommand.new("add validation to the form").send_to_main_session?   # => false
    class AiCommand
      KNOWN_VERBS = %w[claude new bash main].freeze

      # Pattern: optional VERB, WORKSPACE, dash separator, instructions (multiline, case-insensitive).
      PATTERN = /\A(?:(?<verb>claude|new|bash|main)\s+)?(?<workspace>\S+)\s+-\s+(?<instructions>.+)\z/mi

      attr_reader :verb, :workspace, :instructions

      # @param body [String] the ai: message body (ai: prefix already stripped)
      def initialize(body)
        m = PATTERN.match(body.to_s.strip)
        if m
          @verb         = m[:verb]&.downcase
          @workspace    = m[:workspace]
          @instructions = m[:instructions].strip
        else
          @verb         = nil
          @workspace    = nil
          @instructions = body.to_s.strip
        end
      end

      # Returns true when this command should be delivered to the main (pane 1) session.
      # Verbs: claude, main.
      #
      # @return [Boolean]
      def send_to_main_session?
        %w[claude main].include?(verb)
      end

      # Returns true when this command should open a new pane.
      # Verb: new, or no recognized verb/workspace (falls through to DispatchAiCommand).
      #
      # Reserved for future routing use.
      #
      # @return [Boolean]
      def new_session?
        verb == "new" || (verb.nil? && workspace.nil?)
      end

      # Returns true when this command should open a new bash pane.
      # Verb: bash.
      #
      # Reserved for future routing use.
      #
      # @return [Boolean]
      def bash_session?
        verb == "bash"
      end
    end
  end
end
