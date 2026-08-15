# frozen_string_literal: true

require "work_coordinator/ports/restart_state_repository"
require "work_coordinator/persistence/models/restart_state_record"

module WorkCoordinator
  module Adapters
    # Persists restart bookkeeping to the single `restart_states` row,
    # converting between the ActiveRecord row and
    # {Ports::RestartStateRepository::State}.
    class SqliteRestartStateRepository
      include Ports::RestartStateRepository

      # @return [Ports::RestartStateRepository::State, nil]
      def load
        record&.then { to_domain(_1) }
      end

      # @param attempt [Integer]
      # @return [Ports::RestartStateRepository::State] the saved state
      def save(attempt:)
        row = Persistence::Models::RestartStateRecord.find_or_initialize_by(id: singleton_id)
        row.attempt = attempt
        row.save!
        to_domain(row)
      end

      # @return [void]
      def clear
        record&.destroy
        nil
      end

      private

      def record
        Persistence::Models::RestartStateRecord.find_by(id: singleton_id)
      end

      def singleton_id
        Persistence::Models::RestartStateRecord::SINGLETON_ID
      end

      def to_domain(row)
        Ports::RestartStateRepository::State.new(attempt: row.attempt)
      end
    end
  end
end
