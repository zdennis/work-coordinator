# frozen_string_literal: true

require "open3"
require "shellwords"
require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Adapters
    class TmuxAgentSession
      include Ports::AgentSession

      def initialize(work_item_repo:)
        @work_item_repo = work_item_repo
      end

      def start_session(work_item_id:)
        work_item = @work_item_repo.find(work_item_id)
        target = work_item&.workspace_name
        raise ArgumentError, "work item #{work_item_id} has no workspace_name" if target.nil? || target.empty?

        target
      end

      def deliver(session_id:, message:)
        cmd = ["tmux", "send-keys", "-t", session_id, Shellwords.escape(message), "Enter"]
        out, status = run_command(cmd)
        raise "tmux send-keys failed: #{out}" unless status.success?
      end

      def end_session(**)
        nil
      end

      def active_session(work_item_id:)
        work_item = @work_item_repo.find(work_item_id)
        target = work_item&.workspace_name
        return nil if target.nil? || target.empty?

        out, status = run_command(["tmux", "list-panes", "-a", "-F",
                                   "\#{session_name}:\#{window_index}.\#{pane_index}"])
        return nil unless status.success?

        out.split("\n").include?(target) ? target : nil
      end

      private

      def run_command(cmd)
        Open3.capture2e(*cmd)
      end
    end
  end
end
