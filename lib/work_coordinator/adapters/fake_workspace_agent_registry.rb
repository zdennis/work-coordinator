# frozen_string_literal: true

require "work_coordinator/ports/workspace_agent_registry"
require "work_coordinator/adapters/process_liveness"

module WorkCoordinator
  module Adapters
    # In-memory stand-in for {SqliteWorkspaceAgentRegistry}, for tests that do
    # not need the database.
    class FakeWorkspaceAgentRegistry
      include Ports::WorkspaceAgentRegistry
      include ProcessLiveness

      def initialize
        @entries = {}
      end

      # @return [Hash] `{ok: true}` or `{ok: false, error: "already_registered"}`
      def register(workspace_name:, socket_path:, pipeline:, epoch:, pid: nil)
        existing = @entries[workspace_name]
        if existing && existing[:epoch] != epoch && !stale_process?(existing[:pid])
          return { ok: false, error: "already_registered" }
        end

        @entries[workspace_name] = { socket_path: socket_path, pipeline: pipeline, epoch: epoch, pid: pid }
        { ok: true }
      end

      # @return [Hash] `{ok: true}`
      def unregister(workspace_name:)
        @entries.delete(workspace_name)
        { ok: true }
      end

      # @return [Hash{Symbol=>Object}, nil]
      def find(workspace_name)
        @entries[workspace_name]&.dup
      end

      # @return [Boolean]
      def registered?(workspace_name)
        @entries.key?(workspace_name)
      end

      # @return [Array<Hash{Symbol=>Object}>]
      def all
        @entries.map { |name, entry| { workspace_name: name }.merge(entry) }
      end

      # @return [void]
      def clear
        @entries.clear
      end
    end
  end
end
