# frozen_string_literal: true

require "logger"
require "work_coordinator/ports/workspace_agent_registry"
require "work_coordinator/adapters/process_liveness"
require "work_coordinator/persistence/models/workspace_agent_registration_record"

module WorkCoordinator
  module Adapters
    # Persists workspace agent registrations to the
    # `workspace_agent_registrations` table.
    class SqliteWorkspaceAgentRegistry
      include Ports::WorkspaceAgentRegistry
      include ProcessLiveness

      # @param logger [Logger]
      def initialize(logger: Logger.new(IO::NULL))
        @logger = logger
      end

      # A workspace can only be claimed once. Re-registering under the same
      # epoch is the same process restarting its listener, so it refreshes the
      # row; a different epoch is a second process and is refused — unless the
      # process that holds the claim is gone, in which case the stale
      # registration is evicted.
      #
      # @return [Hash] `{ok: true}` or `{ok: false, error: "already_registered"}`
      def register(workspace_name:, socket_path:, pipeline:, epoch:, pid: nil)
        record = model.find_or_initialize_by(workspace_name: workspace_name)

        if record.persisted? && record.epoch != epoch && !claim_reclaimable?(record, workspace_name)
          return { ok: false, error: "already_registered" }
        end

        action = record.persisted? ? "refreshed" : "registered"
        record.update!(socket_path: socket_path, pipeline: pipeline, epoch: epoch, pid: pid)
        @logger.debug "WorkspaceAgentRegistry#register: #{action} workspace=#{workspace_name.inspect} " \
                      "socket=#{socket_path.inspect} epoch=#{epoch.inspect} pid=#{pid.inspect}"
        { ok: true }
      end

      # @return [Hash] `{ok: true}`
      def unregister(workspace_name:)
        count = model.where(workspace_name: workspace_name).delete_all
        status = count.positive? ? "removed" : "not found"
        @logger.debug "WorkspaceAgentRegistry#unregister: workspace=#{workspace_name.inspect} (#{status})"
        { ok: true }
      end

      # @return [Hash{Symbol=>Object}, nil]
      def find(workspace_name)
        record = model.find_by(workspace_name: workspace_name)
        record && { socket_path: record.socket_path, pipeline: record.pipeline, epoch: record.epoch,
                    pid: record.pid }
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
            epoch: record.epoch,
            pid: record.pid
          }
        end
      end

      # @return [void]
      def clear
        model.delete_all
      end

      private

      def model = Persistence::Models::WorkspaceAgentRegistrationRecord

      # @return [Boolean] true when the existing claim can be taken over
      def claim_reclaimable?(record, workspace_name)
        if stale_process?(record.pid)
          @logger.debug "WorkspaceAgentRegistry#register: evicting stale registration " \
                        "workspace=#{workspace_name.inspect} old_pid=#{record.pid.inspect}"
          true
        else
          @logger.debug "WorkspaceAgentRegistry#register: rejected workspace=#{workspace_name.inspect} " \
                        "(already registered with different epoch)"
          false
        end
      end
    end
  end
end
