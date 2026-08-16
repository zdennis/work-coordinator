# frozen_string_literal: true

require "work_coordinator/ports/work_item_repository"
require "work_coordinator/domain/work_item"
require "work_coordinator/persistence/models/work_item_record"

module WorkCoordinator
  module Adapters
    # Persists work items to the `work_items` table, converting between the
    # ActiveRecord row and {Domain::WorkItem} (symbols on the domain side,
    # strings in the database).
    class SqliteWorkItemRepository
      include Ports::WorkItemRepository

      # Inserts or updates the row matching the work item's id.
      #
      # @param work_item [Domain::WorkItem]
      # @return [Domain::WorkItem] the argument, unchanged
      def save(work_item)
        record = Persistence::Models::WorkItemRecord.find_or_initialize_by(id: work_item.id)
        record.assign_attributes(to_attributes(work_item))
        record.save!
        work_item
      end

      # @param id [String]
      # @return [Domain::WorkItem, nil]
      def find(id)
        record = Persistence::Models::WorkItemRecord.find_by(id: id)
        record && to_domain(record)
      end

      # @param external_reference [String] ticket key, e.g. "ABC-123"
      # @return [Domain::WorkItem, nil]
      def find_by_external_reference(external_reference)
        record = Persistence::Models::WorkItemRecord.find_by(external_reference: external_reference)
        record && to_domain(record)
      end
      alias find_by_ref find_by_external_reference

      # @param state [Symbol, String, nil] restrict to work items in this state
      # @param project_id [String, nil] restrict to work items belonging to this project
      # @return [Array<Domain::WorkItem>]
      def find_all(state: nil, project_id: nil)
        scope = Persistence::Models::WorkItemRecord.all
        scope = scope.with_state(state) if state
        scope = scope.where(project_id: project_id) if project_id
        scope.map { |r| to_domain(r) }
      end

      # @param id [String]
      # @return [void]
      def delete(id)
        Persistence::Models::WorkItemRecord.find_by(id: id)&.destroy
      end

      private

      def to_attributes(work_item)
        {
          title: work_item.title,
          kind: work_item.kind.to_s,
          external_reference: work_item.external_reference,
          repository: work_item.repository,
          workspace_name: work_item.workspace_name,
          state: work_item.state.to_s,
          phase: work_item.phase&.to_s,
          project_id: work_item.project_id,
          created_at: work_item.created_at,
          updated_at: work_item.updated_at
        }
      end

      def to_domain(record)
        Domain::WorkItem.new(
          id: record.id,
          title: record.title,
          kind: record.kind.to_sym,
          external_reference: record.external_reference,
          repository: record.repository,
          workspace_name: record.workspace_name,
          state: record.state.to_sym,
          phase: record.phase,
          project_id: record.project_id,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end
    end
  end
end
