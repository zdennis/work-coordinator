# frozen_string_literal: true

module WorkCoordinator
  module Ports
    module AiCommandRunner
      # @param body [String] the full freeform instruction
      # @return [String] a project/workspace keyword extracted by the AI
      def extract_project(body:) = raise NotImplementedError

      # @return [Array<String>] names of active workspaces
      def list_projects = raise NotImplementedError

      # @return [Array<String>] names of all workspaces (active and dormant)
      def list_all_projects = raise NotImplementedError

      # @param name [String] workspace name to launch
      # @return [void]
      def launch_workspace(name:) = raise NotImplementedError

      # @param project [String] matched workspace name
      # @param instructions [String] the full freeform instruction
      # @return [String] stdout from the workspace run
      def run_project(project:, instructions:) = raise NotImplementedError

      # @param text [String] raw output to summarize
      # @return [String] 1-3 sentence summary
      def summarize(text:) = raise NotImplementedError
    end
  end
end
