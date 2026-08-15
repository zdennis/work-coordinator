# frozen_string_literal: true

module WorkCoordinator
  module Adapters
    # In-memory stand-in for {SqliteInboundMessageRepository}, for tests.
    class InMemoryInboundMessageRepository
      # @return [Array<String>] guids recorded, in the order they arrived
      attr_reader :recorded

      # @param seen [Array<String>] guids to treat as already handled
      def initialize(seen: [])
        @recorded = seen.dup
      end

      # @param guid [String]
      # @return [Boolean]
      def seen?(guid)
        @recorded.include?(guid)
      end

      # Marks the guid handled. Recording the same guid twice is a no-op.
      #
      # @param guid [String]
      # @return [void]
      def record(guid)
        @recorded << guid unless @recorded.include?(guid)
      end
    end
  end
end
