module WorkCoordinator
  module Domain
    Decision = Data.define(:id, :work_item_id, :description, :rationale, :decided_at)
  end
end
