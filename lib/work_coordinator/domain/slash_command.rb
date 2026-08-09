# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Parses the body of an ai: message using slash command shorthand.
    #
    # Recognized format:  /VERB WORKSPACE [args]
    #
    # @example
    #   SlashCommand.new("/build GE add OAuth support").recognized?  # => true
    #   SlashCommand.new("/clear GE").instructions                   # => "/clear"
    #   SlashCommand.new("/stop GE").instructions                    # => "C-c"
    class SlashCommand
      KNOWN_VERBS = %w[build research clear test fix review commit push pr stop].freeze
      PATTERN = %r{\A/(?<verb>\w+)\s+(?<workspace>\S+)(?:\s+(?<args>.+))?\z}mi

      attr_reader :verb, :workspace, :args

      def initialize(body)
        m = PATTERN.match(body.to_s.strip)
        if m
          @verb      = m[:verb]&.downcase
          @workspace = m[:workspace]
          @args      = m[:args]&.strip
        else
          @verb      = nil
          @workspace = nil
          @args      = nil
        end
      end

      def recognized?
        KNOWN_VERBS.include?(verb)
      end

      def send_to_main_session?
        recognized?
      end

      def instructions # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
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
        end
      end
    end
  end
end
