# frozen_string_literal: true

module WorkCoordinator
  module Ports
    module WorkItemRepository
      def find(id) = raise NotImplementedError
      def find_all(status: nil) = raise NotImplementedError
      def save(work_item) = raise NotImplementedError
      def delete(id) = raise NotImplementedError
    end
  end
end
