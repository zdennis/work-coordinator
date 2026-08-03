# frozen_string_literal: true

module WorkCoordinator
  module Domain
    Decision = Data.define(:id, :work_item_id, :title, :status, :context, :decision_text, :consequences, :source,
                           :created_at) do
      def proposed?   = status == :proposed
      def accepted?   = status == :accepted
      def superseded? = status == :superseded
      def rejected?   = status == :rejected
    end
  end
end
