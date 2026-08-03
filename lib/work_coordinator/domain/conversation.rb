# frozen_string_literal: true

module WorkCoordinator
  module Domain
    Conversation = Data.define(:id, :work_item_id, :message_thread_id, :agent_session, :last_inbound_at,
                               :last_outbound_at)
  end
end
