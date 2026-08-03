# frozen_string_literal: true

require "securerandom"
require "work_coordinator/domain/work_item"

module WorkCoordinator
  module Application
    class RegisterWorkItem
      def initialize(work_item_repo:, event_store:)
        @work_item_repo = work_item_repo
        @event_store = event_store
      end

      def call(title:, kind:, external_reference: nil, repository: nil, workspace_name: nil)
        work_item = build_work_item(title: title, kind: kind, external_reference: external_reference,
                                    repository: repository, workspace_name: workspace_name)
        @work_item_repo.save(work_item)
        record_created_event(work_item, title: title, kind: kind, external_reference: external_reference)
        work_item
      end

      private

      def build_work_item(title:, kind:, external_reference:, repository:, workspace_name:)
        now = Time.now
        Domain::WorkItem.new(
          id: SecureRandom.uuid,
          title: title,
          kind: kind,
          external_reference: external_reference,
          repository: repository,
          workspace_name: workspace_name,
          state: :created,
          phase: nil,
          created_at: now,
          updated_at: now
        )
      end

      def record_created_event(work_item, title:, kind:, external_reference:)
        @event_store.append(
          type: "work_item.created",
          work_item_id: work_item.id,
          source: "system",
          data: { title: title, kind: kind, external_reference: external_reference }
        )
      end
    end
  end
end
