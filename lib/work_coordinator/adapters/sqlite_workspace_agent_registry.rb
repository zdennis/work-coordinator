# frozen_string_literal: true

require "work_coordinator/ports/workspace_agent_registry"
require "work_coordinator/persistence/models/workspace_agent_registration_record"

module WorkCoordinator
  module Adapters
    # Persists workspace agent registrations to the
    # `workspace_agent_registrations` table.
    class SqliteWorkspaceAgentRegistry
      include Ports::WorkspaceAgentRegistry

      # A workspace can only be claimed once. Re-registering under the same
      # epoch is the same process restarting its listener, so it refreshes the
      # row; a different epoch is a second process and is refused.
      #
      # @return [Hash] `{ok: true}` or `{ok: false, error: "already_registered"}`
      def register(workspace_name:, socket_path:, pipeline:, epoch:)
        record = model.find_or_initialize_by(workspace_name: workspace_name)
        return { ok: false, error: "already_registered" } if record.persisted? && record.epoch != epoch

        record.update!(socket_path: socket_path, pipeline: pipeline, epoch: epoch)
        { ok: true }
      end

      # @return [Hash] `{ok: true}`
      def unregister(workspace_name:)
        model.where(workspace_name: workspace_name).delete_all
        { ok: true }
      end

      # @return [Hash{Symbol=>Object}, nil]
      def find(workspace_name)
        record = model.find_by(workspace_name: workspace_name)
        record && { socket_path: record.socket_path, pipeline: record.pipeline, epoch: record.epoch }
      end

      # @return [Boolean]
      def registered?(workspace_name)
        model.exists?(workspace_name: workspace_name)
      end

      # @return [Array<Hash{Symbol=>Object}>]
      def all
        model.all.map do |record|
          {
            workspace_name: record.workspace_name,
            socket_path: record.socket_path,
            pipeline: record.pipeline,
            epoch: record.epoch
          }
        end
      end

      # @return [void]
      def clear
        model.delete_all
      end

      private

      def model = Persistence::Models::WorkspaceAgentRegistrationRecord
    end
  end
end
