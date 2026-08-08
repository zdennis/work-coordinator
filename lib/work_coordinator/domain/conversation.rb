# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Links a work item to the message thread and agent session that carry its
    # back-and-forth with the human.
    #
    # @!attribute [r] id
    #   @return [String]
    # @!attribute [r] work_item_id
    #   @return [String]
    # @!attribute [r] message_thread_id
    #   @return [String, nil] transport-side thread identifier
    # @!attribute [r] agent_session
    #   @return [String, nil] session identifier the agent is reachable at
    # @!attribute [r] last_inbound_at
    #   @return [Time, nil]
    # @!attribute [r] last_outbound_at
    #   @return [Time, nil]
    Conversation = Data.define(:id, :work_item_id, :message_thread_id, :agent_session, :last_inbound_at,
                               :last_outbound_at)
  end
end
