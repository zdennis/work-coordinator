# frozen_string_literal: true

require "work_coordinator/ports/project_repository"
require "work_coordinator/domain/project"
require "work_coordinator/persistence/models/project_record"

module WorkCoordinator
  module Adapters
    # Persists projects to the `projects` table, converting between the
    # ActiveRecord row and {Domain::Project}.
    class SqliteProjectRepository
      include Ports::ProjectRepository

      # @param project [Domain::Project]
      # @return [Domain::Project] the saved project
      def save(project)
        record = Persistence::Models::ProjectRecord.find_or_initialize_by(id: project.id)
        record.assign_attributes(to_attributes(project))
        record.save!
        to_domain(record)
      end

      # @param id [String]
      # @return [Domain::Project, nil]
      def find(id)
        Persistence::Models::ProjectRecord.find_by(id: id)&.then { to_domain(_1) }
      end

      # Exact case-insensitive match on name OR alias.
      # @param query [String]
      # @return [Domain::Project, nil]
      def find_by_name_or_alias(query)
        q = query.downcase.strip
        Persistence::Models::ProjectRecord
          .where("LOWER(name) = ? OR LOWER(alias) = ?", q, q)
          .first&.then { to_domain(_1) }
      end

      # @return [Array<Domain::Project>]
      def find_all
        Persistence::Models::ProjectRecord.all.map { to_domain(_1) }
      end

      # @return [Domain::Project, nil]
      def default_project
        Persistence::Models::ProjectRecord.default_project&.then { to_domain(_1) }
      end

      # Clears is_default on every project, then saves this one as default.
      # Runs in a single transaction to protect the single-default invariant.
      # @param project [Domain::Project]
      # @return [Domain::Project] the saved default project
      def set_default(project) # rubocop:disable Naming/AccessorMethodName
        ActiveRecord::Base.transaction do
          Persistence::Models::ProjectRecord.update_all(is_default: false)
          save(project.with(is_default: true))
        end
      end

      # @param id [String]
      # @return [void]
      def delete(id)
        Persistence::Models::ProjectRecord.find_by(id: id)&.destroy
      end

      private

      def to_attributes(project)
        {
          name: project.name,
          alias: project.alias,
          workspace_name: project.workspace_name,
          is_default: project.is_default,
          created_at: project.created_at,
          updated_at: project.updated_at
        }
      end

      def to_domain(record)
        Domain::Project.new(
          id: record.id,
          name: record.name,
          alias: record.alias,
          workspace_name: record.workspace_name,
          is_default: record.is_default,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end
    end
  end
end
