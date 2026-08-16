# frozen_string_literal: true

require "work_coordinator/application/register_work_item"

module WorkCoordinator
  module Application
    # Gives a dispatched command an identity before it is forwarded, so status,
    # phase updates, and notifications have a reference to hang off.
    #
    # References are coordinator-issued and scoped to the coordinator's role:
    # HOME-1, HOME-2, ... at role "home"; WORK-1, WORK-2, ... at role "work".
    # The prefix is derived from the role at construction time so different
    # coordinator instances maintain independent namespaces.
    class RegisterCommandWorkItem
      # Default prefix used when no role is configured.
      # @return [String]
      DEFAULT_PREFIX = "WC"

      # @param register_work_item [RegisterWorkItem]
      # @param work_item_repo [Ports::WorkItemRepository] read to allocate the next reference
      # @param ref_prefix [String] uppercase prefix for generated refs, e.g. "HOME" or "WORK"
      def initialize(register_work_item:, work_item_repo:, ref_prefix: DEFAULT_PREFIX)
        @register_work_item = register_work_item
        @work_item_repo     = work_item_repo
        @ref_prefix         = ref_prefix.to_s.upcase
        @reference_pattern  = /\A#{Regexp.escape(@ref_prefix)}-(\d+)\z/
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
        issued  = @work_item_repo.find_all.filter_map { |wi| @reference_pattern.match(wi.external_reference.to_s) }
        highest = issued.map { |m| m[1].to_i }.max || 0
        "#{@ref_prefix}-#{highest + 1}"
      end
    end
  end
end
