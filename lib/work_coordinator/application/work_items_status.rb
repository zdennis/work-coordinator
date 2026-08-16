# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Formats the coordinator's work items as a plain-text table and, when an
    # inbound message is given, replies with it. Used by both the CLI-facing
    # slash command "/work-items status" and direct callers.
    class WorkItemsStatus
      TITLE_LIMIT = 50

      def initialize(work_item_repo:, message_sender:, config: nil, socket_path: nil)
        @work_item_repo = work_item_repo
        @message_sender = message_sender
        @config         = config
        @socket_path    = socket_path || ENV.fetch("WC_SOCKET", "/tmp/work-coordinator.sock")
      end

      # @param msg [Hash, nil] inbound message to reply to; nil returns the body only
      # @param state [Symbol, nil] restrict to work items in this state
      # @param project_id [String, nil] restrict to work items in this project
      # @return [String] the formatted status table
      def call(msg: nil, state: nil, project_id: nil)
        body = format_body(@work_item_repo.find_all(state: state, project_id: project_id))
        @message_sender.send_message(to: msg[:from], body: body) if msg
        body
      end

      private

      def format_body(items)
        lines = [header, "", format(row_format, "REF", "STATE", "PHASE", "TITLE"), "─" * 84]
        lines.concat(items.empty? ? ["No work items found."] : items.map { |item| row(item) })
        lines.join("\n")
      end

      def header
        running = File.exist?(@socket_path) ? "running" : "not running"
        "Coordinator  role: #{@config&.role || 'unknown'}  |  status: #{running}"
      end

      def row(item)
        format(row_format,
               (item.external_reference || item.id[0, 8]).to_s,
               item.state.to_s,
               item.phase.to_s,
               truncate(item.title.to_s))
      end

      def truncate(title)
        title.length > TITLE_LIMIT ? "#{title[0, TITLE_LIMIT - 1]}…" : title
      end

      def row_format = "%-14s%-22s%-25s%s"
    end
  end
end
