# frozen_string_literal: true

require "work_coordinator/ports/project_repository"

module WorkCoordinator
  module Adapters
    # Hash-backed project storage for tests; nothing survives the process.
    class InMemoryProjectRepository
      include Ports::ProjectRepository

      # @return [void]
      def initialize
        @store = {}
      end

      # @param project [Domain::Project]
      # @return [Domain::Project] the saved project
      def save(project)
        @store[project.id] = project
        project
      end

      # @param id [String]
      # @return [Domain::Project, nil]
      def find(id)
        @store[id]
      end

      # Exact case-insensitive match on name OR alias.
      # @param query [String]
      # @return [Domain::Project, nil]
      def find_by_name_or_alias(query)
        q = query.downcase.strip
        @store.values.find { |p| p.name.downcase == q || p.alias&.downcase == q }
      end

      # @return [Array<Domain::Project>]
      def find_all
        @store.values
      end

      # @return [Domain::Project, nil]
      def default_project
        @store.values.find(&:is_default)
      end

      # Clears is_default on every project, then saves the given one as default.
      # @param project [Domain::Project]
      # @return [Domain::Project] the saved default project
      def set_default(project) # rubocop:disable Naming/AccessorMethodName
        @store.transform_values! { |p| p.with(is_default: false) }
        save(project.with(is_default: true))
      end

      # @param id [String]
      # @return [void]
      def delete(id)
        @store.delete(id)
      end
    end
  end
end
