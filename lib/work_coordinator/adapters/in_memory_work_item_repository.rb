# frozen_string_literal: true

require "work_coordinator/ports/work_item_repository"

module WorkCoordinator
  module Adapters
    # Hash-backed work item storage for tests; nothing survives the process.
    class InMemoryWorkItemRepository
      include Ports::WorkItemRepository

      def initialize
        @store = {}
      end

      def save(work_item)
        @store[work_item.id] = work_item
        work_item
      end

      def find(id)
        @store[id]
      end

      def find_all(status: nil)
        items = @store.values
        status ? items.select { |wi| wi.state == status } : items
      end

      def delete(id)
        @store.delete(id)
      end
    end
  end
end
