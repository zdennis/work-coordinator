# frozen_string_literal: true

module WorkCoordinator
  module Ports
    # Interface for work item storage.
    #
    # Implementors persist and return {Domain::WorkItem} values, keyed by id.
    module WorkItemRepository
      # @param id [String]
      # @return [Domain::WorkItem, nil]
      def find(id) = raise NotImplementedError

      # @param status [Symbol, nil] restrict to work items in this state
      # @return [Array<Domain::WorkItem>]
      def find_all(status: nil) = raise NotImplementedError

      # Inserts or updates the work item.
      #
      # @param work_item [Domain::WorkItem]
      # @return [Domain::WorkItem]
      def save(work_item) = raise NotImplementedError

      # @param id [String]
      # @return [void]
      def delete(id) = raise NotImplementedError
    end
  end
end
