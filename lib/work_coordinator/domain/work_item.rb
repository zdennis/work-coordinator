module WorkCoordinator
  module Domain
    WorkItem = Data.define(:id, :title, :description, :status, :created_at) do
      STATUSES = %w[open in_progress blocked done].freeze
      def open? = status == "open"
      def done? = status == "done"
    end
  end
end
