module WorkCoordinator
  module Domain
    Conversation = Data.define(:id, :work_item_id, :participant_handles, :started_at)
  end
end
