# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Outcome of a {RouteMessage} call.
    #
    # @!attribute [r] routed
    #   @return [Boolean] whether the body reached an agent session
    # @!attribute [r] work_item
    #   @return [Domain::WorkItem, nil] the matched item, if the prefix resolved
    # @!attribute [r] body
    #   @return [String] the message with its reference prefix stripped
    Result = Data.define(:routed, :work_item, :body)

    # Dispatches a human's reply to the agent working the referenced item.
    class RouteMessage
      # Matches a leading ticket reference, e.g. `ABC-123 do the thing`.
      # @return [Regexp]
      PREFIX_PATTERN = /\A([A-Z]+-\d+)\s+(.*)\z/m

      # Matches a reply prefix, e.g. `reply: investigate this`.
      # @return [Regexp]
      REPLY_PATTERN = /\Areply:\s*(.*)\z/mi

      # @param work_item_repo [Ports::WorkItemRepository]
      # @param agent_session [Ports::AgentSession]
      # @param event_store [#append]
      # @return [void]
      def initialize(work_item_repo:, agent_session:, event_store:)
        @work_item_repo = work_item_repo
        @agent_session = agent_session
        @event_store = event_store
      end

      # Delivers the message when its prefix names a known work item with a live
      # session, marking that item active and recording a `human.replied` event.
      # Returns an unrouted result — without raising — when the prefix is
      # missing, unknown, or the item has no live session.
      #
      # @param raw_message [String]
      # @return [Result]
      def call(raw_message:)
        if (reply_match = REPLY_PATTERN.match(raw_message))
          return route_reply(instruction: reply_match[1].strip, raw_message: raw_message)
        end

        match = PREFIX_PATTERN.match(raw_message)
        return Result.new(routed: false, work_item: nil, body: raw_message) unless match

        route_with_prefix(ref: match[1], body: match[2], raw_message: raw_message)
      end

      private

      def route_with_prefix(ref:, body:, raw_message:)
        work_item = @work_item_repo.find_all.find { |wi| wi.external_reference == ref }
        return Result.new(routed: false, work_item: nil, body: body) unless work_item

        session_id = @agent_session.active_session(work_item_id: work_item.id)
        return Result.new(routed: false, work_item: work_item, body: body) unless session_id

        deliver_and_record(session_id: session_id, work_item: work_item, raw_message: raw_message, body: body)
      end

      def route_reply(instruction:, raw_message:)
        event = @event_store.last_of_type(type: "system.notified")
        return Result.new(routed: false, work_item: nil, body: instruction) unless event

        work_item = @work_item_repo.find(event.work_item_id)
        return Result.new(routed: false, work_item: nil, body: instruction) unless work_item

        session_id = @agent_session.active_session(work_item_id: work_item.id)
        return Result.new(routed: false, work_item: work_item, body: instruction) unless session_id

        context = "[#{event.data['ref']}] #{event.data['body']}"
        combined = "Current instruction: #{instruction}\nContext: #{context}"

        deliver_and_record(session_id: session_id, work_item: work_item, raw_message: raw_message, body: combined)
      end

      def deliver_and_record(session_id:, work_item:, raw_message:, body:)
        @agent_session.deliver(session_id: session_id, message: body)
        active_item = work_item.with(state: :active, updated_at: Time.now)
        @work_item_repo.save(active_item)
        @event_store.append(
          type: "human.replied",
          work_item_id: work_item.id,
          source: "human",
          data: { raw_message: raw_message, body: body }
        )
        Result.new(routed: true, work_item: active_item, body: body)
      end
    end
  end
end
