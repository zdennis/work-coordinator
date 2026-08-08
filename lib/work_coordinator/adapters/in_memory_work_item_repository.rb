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

      # @param status [Symbol, String, nil] restrict to items in this state
      # @return [Array<Domain::WorkItem>]
      def find_all(status: nil)
        items = @store.values
        status ? items.select { |wi| wi.state == status } : items
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
