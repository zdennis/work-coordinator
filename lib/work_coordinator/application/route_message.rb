# frozen_string_literal: true

module WorkCoordinator
  module Application
    Result = Data.define(:routed, :work_item, :body)

    class RouteMessage
      PREFIX_PATTERN = /\A([A-Z]+-\d+)\s+(.*)\z/m

      def initialize(work_item_repo:, agent_session:, event_store:)
        @work_item_repo = work_item_repo
        @agent_session = agent_session
        @event_store = event_store
      end

      def call(raw_message:)
        match = PREFIX_PATTERN.match(raw_message)
        return Result.new(routed: false, work_item: nil, body: raw_message) unless match

        ref = match[1]
        body = match[2]
        work_item = @work_item_repo.find_all.find { |wi| wi.external_reference == ref }
        return Result.new(routed: false, work_item: nil, body: body) unless work_item

        session_id = @agent_session.active_session(work_item_id: work_item.id)
        return Result.new(routed: false, work_item: work_item, body: body) unless session_id

        deliver_and_record(session_id: session_id, work_item: work_item, raw_message: raw_message, body: body)
      end

      private

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
