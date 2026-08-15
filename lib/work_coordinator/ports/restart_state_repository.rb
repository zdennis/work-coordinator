# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for the coordinator's restart bookkeeping.
    #
    # Exactly one state exists at a time, and only while a restart is in
    # flight: the pre-`exec` process saves it, the freshly booted process
    # loads it to decide whether to announce, then clears it.
    module RestartStateRepository
      # The persisted restart state. `attempt` counts how many restarts have
      # been attempted in the current chain, so a boot loop can be capped.
      State = Data.define(:attempt)

      # @return [State, nil] nil when no restart is in flight
      def load = raise NotImplementedError

      # Upserts the single state.
      # @param attempt [Integer]
      # @return [State] the saved state
      def save(attempt:) = raise NotImplementedError

      # Removes the state. A no-op when none is stored.
      # @return [void]
      def clear = raise NotImplementedError
    end
  end
end
