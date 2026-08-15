# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for the git operations the self-update flow needs.
    #
    # Implementors operate on a single checkout fixed at construction time.
    module GitRunner
      # Raised when a git operation fails.
      class Error < StandardError; end

      # @return [Boolean] true when the working tree has uncommitted changes
      def dirty? = raise NotImplementedError

      # Fetches and merges the upstream branch.
      #
      # @raise [StandardError] when git reports failure
      # @return [void]
      def pull = raise NotImplementedError

      # @param sha [String] the revision to count from, exclusive
      # @return [Integer] commits reachable from HEAD but not from sha
      def commits_since(sha) = raise NotImplementedError

      # @return [String] the abbreviated sha of HEAD
      def current_sha = raise NotImplementedError

      # @return [String, nil] the tag pointing exactly at HEAD, or nil
      def current_tag = raise NotImplementedError
    end
  end
end
