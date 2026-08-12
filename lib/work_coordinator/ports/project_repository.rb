# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for project storage.
    #
    # Implementors persist and return {Domain::Project} values, keyed by id.
    module ProjectRepository
      # @param id [String]
      # @return [Domain::Project, nil]
      def find(id) = raise NotImplementedError

      # Exact case-insensitive match on name OR alias.
      # @param query [String]
      # @return [Domain::Project, nil]
      def find_by_name_or_alias(query) = raise NotImplementedError

      # @return [Array<Domain::Project>]
      def find_all = raise NotImplementedError

      # @return [Domain::Project, nil]
      def default_project = raise NotImplementedError

      # Upserts the project.
      # @param project [Domain::Project]
      # @return [Domain::Project]
      def save(project) = raise NotImplementedError

      # Clears is_default on every other project, then persists this one
      # with is_default: true. Runs in a single transaction.
      # @param project [Domain::Project]
      # @return [Domain::Project] the saved default project
      def set_default(project) = raise NotImplementedError # rubocop:disable Naming/AccessorMethodName

      # @param id [String]
      # @return [void]
      def delete(id) = raise NotImplementedError
    end
  end
end
