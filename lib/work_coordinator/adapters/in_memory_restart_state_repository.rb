# frozen_string_literal: true

require "work_coordinator/ports/restart_state_repository"

module WorkCoordinator
  module Adapters
    # In-process restart state storage for tests; nothing survives the process.
    class InMemoryRestartStateRepository
      include Ports::RestartStateRepository

      # @return [void]
      def initialize
        @state = nil
      end

      # @return [Ports::RestartStateRepository::State, nil]
      def load
        @state
      end

      # @param attempt [Integer]
      # @return [Ports::RestartStateRepository::State] the saved state
      def save(attempt:)
        @state = Ports::RestartStateRepository::State.new(attempt: attempt)
      end

      # @return [void]
      def clear
        @state = nil
      end
    end
  end
end
