# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Splits the optional leading role token off an ai: message body.
    #
    # The role is a bare word immediately followed by a colon — `home: ...`.
    # It is the first thing the text grammar looks for, before the verb and
    # before the `WORKSPACE - instructions` pattern.
    #
    # The colon must be attached to the word and followed by whitespace or the
    # end of the body, which is what keeps `ai:home: fix it` (role) distinct
    # from `ai: home - fix it` (workspace) and from bodies containing a URL.
    #
    # @example
    #   RoleToken.split("home: claude MS - add validation")
    #   # => ["home", "claude MS - add validation"]
    #   RoleToken.split("MS - add validation")
    #   # => [nil, "MS - add validation"]
    module RoleToken
      PATTERN = /\A(?<role>[a-z0-9][a-z0-9_-]*):(?:[ \t]+|\z)/i

      # @param body [String, nil] the ai: message body (ai: prefix already stripped)
      # @return [Array(String, String)] the downcased role (or nil) and the remaining body
      def self.split(body)
        text = body.to_s.strip
        m = PATTERN.match(text)
        return [nil, text] unless m

        [m[:role].downcase, text[m.end(0)..].to_s.strip]
      end
    end
  end
end
