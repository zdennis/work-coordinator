# frozen_string_literal: true

require "fileutils"
require "json"
require "logger"
require "securerandom"
require "socket"

module WorkCoordinator
  module Adapters
    # Listens on its own Unix domain socket for JSON status reports from
    # workspace agents and turns each one into a domain action. Every
    # connection carries exactly one message and receives exactly one reply
    # before it is closed — the reply tells the agent whether to keep going.
    #
    # This is deliberately not a {Ports::MessageReceiver}: the messages are
    # agent telemetry, not human conversation, and they are not routed into an
    # agent pane.
    class WorkspaceStatusReceiver
      # @param socket_path [String]
      # @param work_item_repo [Ports::WorkItemRepository]
      # @param event_store [#append]
      # @param complete_work_item [#call] `call(work_item_id:, summary:)`
      # @param notify_human [#call] `call(work_item_id:, body:)`
      # @param inform_human [#call] `call(work_item_id:, body:, work_item:)`
      # @param logger [Logger]
      def initialize(work_item_repo:, event_store:, complete_work_item:, notify_human:, inform_human:,
                     socket_path: "/tmp/work-coordinator-status.sock",
                     logger: Logger.new(IO::NULL))
        @socket_path = socket_path
        @work_item_repo = work_item_repo
        @event_store = event_store
        @complete_work_item = complete_work_item
        @notify_human = notify_human
        @inform_human = inform_human
        @logger = logger
        @epoch = "wc-#{SecureRandom.hex(8)}"
        @processed_message_ids = Set.new
        @last_sequence = {}
        @server = nil
        @stop_requested = false
      end

      # @return [String] identifier for this listener's lifetime, echoed in every ok reply
      attr_reader :epoch

      # Replaces any stale socket file, then accepts connections until {#stop}.
      #
      # @return [void]
      def start
        FileUtils.rm_f(@socket_path)
        @server = UNIXServer.new(@socket_path)
        until @stop_requested
          conn = accept_connection || break
          handle_connection(conn)
        end
      end

      # Closes the listener and removes the socket file, unblocking {#start}.
      #
      # @return [void]
      def stop
        @stop_requested = true
        @server&.close
        FileUtils.rm_f(@socket_path) if @socket_path
      rescue StandardError
        nil
      end

      private

      def accept_connection
        @server.accept
      rescue IOError, Errno::EBADF
        nil
      end

      def handle_connection(conn)
        line = conn.gets&.chomp
        return if line.nil? || line.empty?

        message = parse(line)
        return if message.nil?

        reply(conn, dispatch(message))
      rescue StandardError => e
        warn "[WorkspaceStatusReceiver] dropping message: #{e.class}: #{e.message}"
      ensure
        conn.close rescue nil # rubocop:disable Style/RescueModifier
      end

      def parse(line)
        JSON.parse(line)
      rescue JSON::ParserError => e
        warn "[WorkspaceStatusReceiver] dropping malformed JSON message: #{e.message}"
        nil
      end

      def reply(conn, payload)
        conn.puts(JSON.generate(payload))
      end

      def ok = { ok: true, epoch: @epoch }

      # Runs the gate checks — dedup, then ordering, then the work item's
      # existence and state — before handing off to a type handler.
      def dispatch(message)
        message_id = message["message_id"]
        return ok if message_id && @processed_message_ids.include?(message_id)

        out_of_sequence = check_sequence(message)
        return out_of_sequence if out_of_sequence

        ref = message["work_item_ref"]
        work_item = ref && @work_item_repo.find_by_external_reference(ref)
        return { ok: false, error: "unknown_work_item", ref: ref, action: "give_up" } unless work_item
        if work_item.terminal?
          return { ok: false, error: "terminal_state", state: work_item.state.to_s, action: "abort_pipeline" }
        end

        accept(message, work_item)
      end

      def accept(message, work_item)
        handle(message, work_item)
        @processed_message_ids << message["message_id"] if message["message_id"]
        record_sequence(message)
        ok
      end

      def sequence_key(message) = [message["workspace"], message["work_item_ref"]]

      def check_sequence(message)
        sequence = message["sequence"]
        return nil unless sequence

        last = @last_sequence[sequence_key(message)]
        return nil if last.nil? || sequence > last

        { ok: false, error: "out_of_sequence", last_sequence: last, action: "drop" }
      end

      def record_sequence(message)
        sequence = message["sequence"]
        @last_sequence[sequence_key(message)] = sequence if sequence
      end

      def handle(message, work_item) # rubocop:disable Metrics/AbcSize
        type = message["type"]
        ref  = message["work_item_ref"]
        ws   = message["workspace"]
        @logger.debug "WorkspaceStatusReceiver: type=#{type.inspect} workspace=#{ws.inspect} ref=#{ref.inspect}"
        case type
        when "status_update"     then handle_status_update(message, work_item)
        when "phase_change"      then handle_phase_change(message, work_item)
        when "pipeline_advanced" then handle_pipeline_advanced(message, work_item)
        when "task_complete"
          @logger.debug "WorkspaceStatusReceiver: task_complete for #{ref.inspect} — completing work item"
          @complete_work_item.call(work_item_id: work_item.id, summary: message["summary"])
        when "error" then @inform_human.call(work_item_id: work_item.id, body: message["message"], work_item: work_item)
        else warn "[WorkspaceStatusReceiver] dropping message with unknown type: #{type.inspect}"
        end
      end

      def handle_status_update(message, work_item)
        append(work_item, "agent.status_update", message, message: message["message"])
        @inform_human.call(work_item_id: work_item.id, body: message["message"], work_item: work_item)
      end

      def handle_phase_change(message, work_item)
        @work_item_repo.save(work_item.with(phase: message["phase"], updated_at: Time.now))
        append(work_item, "agent.phase_changed", message, phase: message["phase"])
        @inform_human.call(work_item_id: work_item.id, body: "phase: #{message['phase']}", work_item: work_item)
      end

      def handle_pipeline_advanced(message, work_item)
        append(work_item, "agent.pipeline_advanced", message,
               from_pane: message["from_pane"], to_pane: message["to_pane"])
      end

      def append(work_item, type, message, **data)
        @event_store.append(
          type: type,
          work_item_id: work_item.id,
          source: "agent",
          data: {
            workspace: message["workspace"],
            work_item_ref: message["work_item_ref"],
            message_id: message["message_id"],
            **data
          }
        )
      end
    end
  end
end
