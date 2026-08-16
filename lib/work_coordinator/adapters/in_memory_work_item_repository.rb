# frozen_string_literal: true

require "work_coordinator/ports/work_item_repository"

module WorkCoordinator
  module Adapters
    # Hash-backed work item storage for tests; nothing survives the process.
    class InMemoryWorkItemRepository
      include Ports::WorkItemRepository

      # @return [void]
      def initialize
        @store = {}
      end

      # Stores or replaces the work item keyed by its id.
      #
      # @param work_item [Domain::WorkItem]
      # @return [Domain::WorkItem] the argument, unchanged
      def save(work_item)
        @store[work_item.id] = work_item
        work_item
      end

      # @param id [String]
      # @return [Domain::WorkItem, nil]
      def find(id)
        @store[id]
      end

      # @param external_reference [String] ticket key, e.g. "ABC-123"
      # @return [Domain::WorkItem, nil]
      def find_by_external_reference(external_reference)
        @store.values.find { |wi| wi.external_reference == external_reference }
      end
      alias find_by_ref find_by_external_reference

      # @param state [Symbol, String, nil] restrict to items in this state
      # @param project_id [String, nil] restrict to items belonging to this project
      # @return [Array<Domain::WorkItem>]
      def find_all(state: nil, project_id: nil)
        items = @store.values
        items = items.select { |wi| wi.state == state } if state
        items = items.select { |wi| wi.project_id == project_id } if project_id
        items
      end

      # @return [Array<Domain::WorkItem>] items blocked on a human reply
      def find_all_waiting_for_human
        find_all(state: :waiting_for_human)
      end

      # Removes the work item with the given id, if present.
      #
      # @param id [String]
      # @return [Domain::WorkItem, nil] the removed item, or nil if not found
      def delete(id)
        @store.delete(id)
      end
    end
  end
end
