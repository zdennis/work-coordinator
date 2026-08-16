# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for tracking which workspace agents are live and where to reach
    # them. Each registration names a workspace, the socket its agent listens
    # on, whether it is mid-pipeline, and the epoch of the process that claimed
    # it — the epoch is what distinguishes an idempotent re-register from a
    # second process trying to take the same workspace.
    module WorkspaceAgentRegistry
      # Claims a workspace for an agent process.
      #
      # @param workspace_name [String]
      # @param socket_path [String]
      # @param pipeline [Boolean]
      # @param epoch [String] identifies the registering process
      # @return [Hash] `{ok: true}`, or `{ok: false, error: "already_registered"}`
      #   when a different epoch already holds the workspace
      def register(workspace_name:, socket_path:, pipeline:, epoch:) = raise NotImplementedError

      # @param workspace_name [String]
      # @return [Hash] `{ok: true}`, whether or not a registration existed
      def unregister(workspace_name:) = raise NotImplementedError

      # @param workspace_name [String]
      # @return [Hash{Symbol=>Object}, nil] `{socket_path:, pipeline:, epoch:}`
      def find(workspace_name) = raise NotImplementedError

      # @param workspace_name [String]
      # @return [Boolean]
      def registered?(workspace_name) = raise NotImplementedError

      # @return [Array<Hash{Symbol=>Object}>] `{workspace_name:, socket_path:, pipeline:, epoch:}`
      def all = raise NotImplementedError
    end
  end
end
