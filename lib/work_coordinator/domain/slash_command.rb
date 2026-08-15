# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Parses the body of an ai: message using slash command shorthand.
    #
    # Recognized format:  /VERB WORKSPACE [args]
    #
    # Coordinator verbs address the coordinator itself rather than an agent pane,
    # so they take no workspace:  /restart
    #
    # @example
    #   SlashCommand.new("/build MS add OAuth support").recognized?  # => true
    #   SlashCommand.new("/clear MS").instructions                   # => "/clear"
    #   SlashCommand.new("/stop MS").instructions                    # => "C-c"
    #   SlashCommand.new("/restart").coordinator_command?            # => true
    class SlashCommand
      COORDINATOR_VERBS = %w[restart update].freeze
      KNOWN_VERBS = (%w[build research clear test fix review commit push pr stop] + COORDINATOR_VERBS).freeze
      PATTERN = %r{\A/(?<verb>\w+)(?:\s+(?<workspace>\S+))?(?:\s+(?<args>.+))?\z}i

      attr_reader :verb, :workspace, :args

      def initialize(body)
        m = PATTERN.match(normalize(body))
        verb = m && m[:verb].downcase

        if verb.nil? || malformed?(verb, m)
          @verb = @workspace = @args = nil
        else
          @verb      = verb
          @workspace = m[:workspace]
          @args      = m[:args]&.strip
        end
      end

      def recognized?
        KNOWN_VERBS.include?(verb)
      end

      def coordinator_command?
        COORDINATOR_VERBS.include?(verb)
      end

      # @raise [RuntimeError] for coordinator verbs, which address the coordinator
      #   process rather than an agent pane
      def instructions # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
        raise "No pane instructions for coordinator command: #{verb}" if coordinator_command?

        case verb
        when "build"    then args ? "We're building a feature: #{args}" : "Build a feature"
        when "research" then args ? "Research #{args}" : "Research the current topic"
        when "clear"    then "/clear"
        when "test"     then args ? "Run tests: #{args}" : "Run the test suite"
        when "fix"      then args ? "Fix: #{args}" : "Fix the current issue"
        when "review"   then args ? "Review: #{args}" : "Review the current changes"
        when "commit"   then args ? "Commit: #{args}" : "Commit the current changes"
        when "push"     then "Push the current branch"
        when "pr"       then args ? "Open a pull request: #{args}" : "Open a pull request"
        when "stop"     then "C-c"
        else raise "instructions not defined for recognized verb: #{verb}"
        end
      end

      private

      # "ai: restart" arrives as a bare verb with no leading slash. Prefix one so the
      # pattern sees a slash command, but only on an exact match — "update the readme"
      # must stay free-form text.
      def normalize(body)
        stripped = body.to_s.strip
        COORDINATOR_VERBS.include?(stripped.downcase) ? "/#{stripped.downcase}" : stripped
      end

      # Every verb but a coordinator verb addresses a workspace; without one the
      # command is malformed rather than a command with a nil target. Coordinator
      # verbs are the inverse: any trailing token means this was free-form text.
      def malformed?(verb, match)
        if COORDINATOR_VERBS.include?(verb)
          !match[:workspace].nil?
        else
          match[:workspace].nil?
        end
      end
    end
  end
end
