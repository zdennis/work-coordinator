# frozen_string_literal: true

require "work_coordinator/ports/git_runner"

module WorkCoordinator
  module Adapters
    # In-memory git runner for tests; answers with canned values and records pulls.
    class FakeGitRunner
      include Ports::GitRunner

      # @return [Boolean] whether {#pull} was called
      attr_reader :pulled

      alias pulled? pulled

      # @param dirty [Boolean] answer for {#dirty?}
      # @param commits_since [Integer] answer for {#commits_since}
      # @param sha [String] answer for {#current_sha}
      # @param tag [String, nil] answer for {#current_tag}
      # @param pull_error [String, nil] when set, {#pull} raises with this message
      def initialize(dirty: false, commits_since: 0, sha: "abc1234", tag: nil, pull_error: nil)
        @dirty = dirty
        @commits_since = commits_since
        @sha = sha
        @tag = tag
        @pull_error = pull_error
        @pulled = false
      end

      # @return [Boolean]
      def dirty? = @dirty

      # @raise [Ports::GitRunner::Error] when constructed with `pull_error:`
      # @return [void]
      def pull
        @pulled = true
        raise Ports::GitRunner::Error, @pull_error if @pull_error
      end

      # @param _sha [String]
      # @return [Integer]
      def commits_since(_sha) = @commits_since

      # @return [String]
      def current_sha = @sha

      # @return [String, nil]
      def current_tag = @tag
    end
  end
end
