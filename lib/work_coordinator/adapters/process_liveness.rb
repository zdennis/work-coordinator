# frozen_string_literal: true

module WorkCoordinator
  module Adapters
    # Shared predicate for checking whether a process is still alive.
    # Used by registry adapters to decide whether a stale registration can be
    # evicted.
    module ProcessLiveness
      # @param old_pid [Integer, nil]
      # @return [Boolean] true when the process is definitively gone, false when
      #   it is alive or when liveness cannot be determined
      def stale_process?(old_pid)
        return false if old_pid.nil? || old_pid.zero?

        Process.kill(0, old_pid)
        false               # no exception → process exists
      rescue Errno::ESRCH
        true                # no such process
      rescue Errno::EPERM
        false               # alive but not owned by us
      end
    end
  end
end
