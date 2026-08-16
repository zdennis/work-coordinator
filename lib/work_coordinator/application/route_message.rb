# frozen_string_literal: true

require "logger"

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
    # @!attribute [r] reason
    #   @return [Symbol, nil] why an unrouted message was refused
    # @!attribute [r] human_message
    #   @return [String, nil] text to send back to the human, when they need to act
    Result = Data.define(:routed, :work_item, :body, :reason, :human_message) do
      def initialize(routed:, work_item:, body:, reason: nil, human_message: nil)
        super
      end
    end

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
      # @param workspace_agent_registry [Ports::WorkspaceAgentRegistry, nil] when
      #   given, replies to items in a registered workspace are injected into the
      #   agent rather than typed into its pane
      # @param notify_human [NotifyHuman, nil] told when an injected steer is refused
      # @return [void]
      def initialize(work_item_repo:, agent_session:, event_store:,
                     workspace_agent_registry: nil, notify_human: nil,
                     implicit_reply_enabled: true, dispatch_via_sockets: true,
                     logger: Logger.new(IO::NULL))
        @work_item_repo = work_item_repo
        @agent_session = agent_session
        @event_store = event_store
        @workspace_agent_registry = workspace_agent_registry
        @notify_human = notify_human
        @implicit_reply_enabled = implicit_reply_enabled
        @dispatch_via_sockets = dispatch_via_sockets
        @logger = logger
      end

      # Delivers the message when its prefix names a known work item with a live
      # session, marking that item active and recording a `human.replied` event.
      # Returns an unrouted result — without raising — when the prefix is
      # missing, unknown, or the item has no live session.
      #
      # @param raw_message [String]
      # @return [Result]
      def call(raw_message:)
        @logger.debug "RouteMessage: raw=#{raw_message.inspect}"
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
        @logger.debug "route_with_prefix: ref=#{ref.inspect} workspace=#{work_item&.workspace_name.inspect}"
        return Result.new(routed: false, work_item: nil, body: body) unless work_item

        session_id = @agent_session.active_session(work_item_id: work_item.id)
        return Result.new(routed: false, work_item: work_item, body: body) unless session_id

        deliver_and_record(session_id: session_id, work_item: work_item, raw_message: raw_message, body: body)
      end

      # A reply names its target explicitly (`reply: ABC-123 use Postgres`) or
      # leaves it implicit, in which case exactly one item may be waiting.
      def route_reply(instruction:, raw_message:)
        match = PREFIX_PATTERN.match(instruction)
        resolved = if match
                     resolve_named_reply(ref: match[1], instruction: match[2])
                   elsif !@implicit_reply_enabled
                     return refusal(body: instruction, reason: :implicit_reply_disabled,
                                    human_message: "Implicit replies are disabled. " \
                                                   "Include a work item reference, e.g. `reply: WC-42 ...`.")
                   else
                     resolve_implicit_reply(instruction: instruction)
                   end
        return resolved if resolved.is_a?(Result)

        work_item, instruction = resolved
        deliver_reply(work_item: work_item, instruction: instruction, raw_message: raw_message)
      end

      def resolve_named_reply(ref:, instruction:)
        work_item = @work_item_repo.find_by_external_reference(ref)
        unless work_item
          return refusal(body: instruction, reason: :unknown_reference,
                         human_message: "#{ref} is not a work item I know about.")
        end

        return [work_item, instruction] if work_item.waiting_for_human?

        refusal(body: instruction, work_item: work_item, reason: :not_waiting,
                human_message: not_waiting_message(work_item))
      end

      def resolve_implicit_reply(instruction:)
        waiting = @work_item_repo.find_all_waiting_for_human

        case waiting.length
        when 1 then [waiting.first, instruction]
        when 0
          refusal(body: instruction, reason: :nothing_waiting,
                  human_message: "Nothing is waiting for a reply right now.")
        else
          refusal(body: instruction, reason: :ambiguous_reply,
                  human_message: "#{waiting.length} items are waiting for a reply — name the one you mean, " \
                                 "e.g. `reply: #{waiting.first.external_reference} ...`. " \
                                 "Waiting: #{waiting.map(&:external_reference).join(', ')}.")
        end
      end

      def deliver_reply(work_item:, instruction:, raw_message:)
        session_id = @agent_session.active_session(work_item_id: work_item.id)
        return Result.new(routed: false, work_item: work_item, body: instruction) unless session_id

        deliver_and_record(session_id: session_id, work_item: work_item, raw_message: raw_message,
                           body: reply_body(work_item: work_item, instruction: instruction))
      end

      def reply_body(work_item:, instruction:)
        event = @event_store.last_of_type(type: "system.notified", work_item_id: work_item.id)
        return instruction unless event

        "Current instruction: #{instruction}\nContext: [#{event.data['ref']}] #{event.data['body']}"
      end

      def not_waiting_message(work_item)
        ref = work_item.external_reference
        return "#{ref} is finished." if work_item.completed?
        return "#{ref} was abandoned." if work_item.abandoned?

        "#{ref} is not waiting for a reply (it is #{work_item.state})."
      end

      def refusal(body:, reason:, human_message:, work_item: nil)
        Result.new(routed: false, work_item: work_item, body: body, reason: reason, human_message: human_message)
      end

      # Hands the body to a registered workspace agent as a mid-pipeline steer.
      #
      # @return [Hash, nil] the agent's reply, or nil when the item is not
      #   managed by a registered agent and should go to tmux instead
      def steer(work_item:, body:)
        return nil unless @dispatch_via_sockets

        workspace = work_item.workspace_name
        return nil unless @workspace_agent_registry && workspace && work_item.external_reference
        return nil unless @workspace_agent_registry.registered?(workspace)

        @agent_session.inject(
          workspace_name: workspace,
          work_item_ref: work_item.external_reference,
          body: body
        )
      end

      # A refused steer leaves the item waiting: the human's words never reached
      # the agent, so the question they were answering is still open.
      def steer_refused(work_item:, body:, error:)
        message = "Could not steer #{work_item.external_reference}: #{error}."
        @notify_human&.call(work_item_id: work_item.id, body: message)
        refusal(body: body, work_item: work_item, reason: :inject_failed, human_message: message)
      end

      def deliver_and_record(session_id:, work_item:, raw_message:, body:)
        reply = steer(work_item: work_item, body: body)
        return steer_refused(work_item: work_item, body: body, error: reply[:error]) if reply && !reply[:ok]

        unless reply
          @agent_session.deliver(session_id: session_id, message: body, work_item_ref: work_item.external_reference)
        end
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
