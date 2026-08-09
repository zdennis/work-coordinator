# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Extracts the repository name from a GitHub URL embedded in text.
    #
    # Recognizes URLs of the form:
    #   https://github.com/OWNER/REPO[/...]
    #
    # @example
    #   GithubUrlExtractor.new("https://github.com/acme/my-service/pull/830").repo_name
    #   # => "my-service"
    #
    #   GithubUrlExtractor.new("see PR https://github.com/acme/billing/pull/42").repo_name
    #   # => "billing"
    #
    #   GithubUrlExtractor.new("plain text no url").repo_name
    #   # => nil
    class GithubUrlExtractor
      PATTERN            = %r{https?://github\.com/[^/]+/([^/\s?#]+)}i
      OWNER_REPO_PATTERN = %r{https?://github\.com/([^/\s?#]+/[^/\s?#]+)}i

      def initialize(text)
        @text = text.to_s
      end

      def repo_name
        m = PATTERN.match(@text)
        m && m[1]
      end

      def owner_repo
        m = OWNER_REPO_PATTERN.match(@text)
        m && m[1]
      end
    end
  end
end
