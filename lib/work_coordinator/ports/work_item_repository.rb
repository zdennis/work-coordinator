# frozen_string_literal: true

module WorkCoordinator
  # Port interfaces that the domain and application layers depend on.
  module Ports
    # Interface for work item storage.
    #
    # Implementors persist and return {Domain::WorkItem} values, keyed by id.
    module WorkItemRepository
      # @param id [String]
      # @return [Domain::WorkItem, nil]
      def find(id) = raise NotImplementedError

      # @param external_reference [String] ticket key, e.g. "ABC-123"
      # @return [Domain::WorkItem, nil]
      def find_by_external_reference(external_reference) = raise NotImplementedError

      # @param state [Symbol, nil] restrict to work items in this state
      # @param project_id [String, nil] restrict to work items belonging to this project
      # @return [Array<Domain::WorkItem>]
      def find_all(state: nil, project_id: nil) = raise NotImplementedError

      # Every item currently blocked on a human reply.
      #
      # @return [Array<Domain::WorkItem>]
      def find_all_waiting_for_human = raise NotImplementedError

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
