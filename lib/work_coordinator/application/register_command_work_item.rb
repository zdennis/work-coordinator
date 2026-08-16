# frozen_string_literal: true

require "work_coordinator/application/register_work_item"

module WorkCoordinator
  module Application
    # Gives a dispatched command an identity before it is forwarded, so status,
    # phase updates, and notifications have a reference to hang off.
    #
    # References are coordinator-issued: WC-1, WC-2, ... allocated from the
    # highest WC- reference already stored.
    class RegisterCommandWorkItem
      # Matches a coordinator-issued reference, e.g. `WC-12`.
      # @return [Regexp]
      REFERENCE_PATTERN = /\AWC-(\d+)\z/

      # Prefix for coordinator-issued references.
      # @return [String]
      REFERENCE_PREFIX = "WC"

      # @param register_work_item [RegisterWorkItem]
      # @param work_item_repo [Ports::WorkItemRepository] read to allocate the next reference
      def initialize(register_work_item:, work_item_repo:)
        @register_work_item = register_work_item
        @work_item_repo     = work_item_repo
      end

      # @param title [String] the command as the human phrased it
      # @param workspace_name [String, nil] workspace the command targets
      # @return [Domain::WorkItem]
      def call(title:, workspace_name:)
        @register_work_item.call(
          title: title,
          kind: :adhoc,
          external_reference: next_reference,
          workspace_name: workspace_name,
          initial_state: :active
        )
      end

      private

      def next_reference
        issued  = @work_item_repo.find_all.filter_map { |wi| REFERENCE_PATTERN.match(wi.external_reference.to_s) }
        highest = issued.map { |m| m[1].to_i }.max || 0
        "#{REFERENCE_PREFIX}-#{highest + 1}"
      end
    end
  end
end
