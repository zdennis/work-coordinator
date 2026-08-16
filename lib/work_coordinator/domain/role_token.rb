# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Splits the optional leading role token off an ai: message body.
    #
    # Two forms are recognised (ai: prefix already stripped):
    #
    #   home: claude MS - ...    → role="home", workspace=nil,  body="claude MS - ..."
    #   home:WC what to do       → role="home", workspace="WC", body="what to do"
    #
    # The role is a bare word immediately followed by a colon. The colon must
    # be followed by either whitespace/end (existing form) or a non-whitespace
    # workspace name followed by whitespace/end (new form). This keeps `ai:home:
    # fix it` (role) distinct from `ai: home - fix it` (workspace) and from
    # bodies containing a URL.
    #
    # @example
    #   RoleToken.split("home: claude MS - add validation")
    #   # => ["home", nil, "claude MS - add validation"]
    #   RoleToken.split("home:WC add validation")
    #   # => ["home", "WC", "add validation"]
    #   RoleToken.split("MS - add validation")
    #   # => [nil, nil, "MS - add validation"]
    module RoleToken
      PATTERN = /\A(?<role>[a-z0-9][a-z0-9_-]*):(?:(?<workspace>[^\s:]+)(?:[ \t]+|\z)|(?:[ \t]+|\z))/i

      # @param body [String, nil] the ai: message body (ai: prefix already stripped)
      # @return [Array(String?, String?, String)] downcased role, workspace (or nil), remaining body
      def self.split(body)
        text = body.to_s.strip
        m = PATTERN.match(text)
        return [nil, nil, text] unless m

        [m[:role].downcase, m[:workspace], text[m.end(0)..].to_s.strip]
      end
    end
  end
end
