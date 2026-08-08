# frozen_string_literal: true

module WorkCoordinator
  module Domain
    # Links a work item to the message thread and agent session that carry its
    # back-and-forth with the human.
    #
    # @!attribute [r] id
    #   @return [String] unique identifier for this conversation
    # @!attribute [r] work_item_id
    #   @return [String] ID of the work item this conversation belongs to
    # @!attribute [r] message_thread_id
    #   @return [String, nil] transport-side thread identifier
    # @!attribute [r] agent_session
    #   @return [String, nil] session identifier the agent is reachable at
    # @!attribute [r] last_inbound_at
    #   @return [Time, nil] timestamp of the last message received, or nil if none received yet
    # @!attribute [r] last_outbound_at
    #   @return [Time, nil] timestamp of the last message sent, or nil if none sent yet
    Conversation = Data.define(:id, :work_item_id, :message_thread_id, :agent_session, :last_inbound_at,
                               :last_outbound_at)
  end
end
