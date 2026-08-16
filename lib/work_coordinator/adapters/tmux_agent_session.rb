# frozen_string_literal: true

require "open3"
require "shellwords"
require "work_coordinator/ports/agent_session"

module WorkCoordinator
  module Adapters
    # Talks to agents running in tmux panes. The session identifier is the work
    # item's `workspace_name`, a tmux target of the form
    # `session:window.pane` — this adapter attaches to panes the operator has
    # already opened rather than spawning them.
    class TmuxAgentSession
      include Ports::AgentSession

      # @param work_item_repo [Ports::WorkItemRepository]
      def initialize(work_item_repo:)
        @work_item_repo = work_item_repo
      end

      # Resolves the work item's tmux target without launching anything.
      #
      # @param work_item_id [String]
      # @return [String] the tmux target
      # @raise [ArgumentError] when the work item has no workspace_name
      def start_session(work_item_id:)
        work_item = @work_item_repo.find(work_item_id)
        target = work_item&.workspace_name
        raise ArgumentError, "work item #{work_item_id} has no workspace_name" if target.nil? || target.empty?

        target
      end

      # Types the message into the pane and presses Enter.
      #
      # @param session_id [String] tmux target
      # @param message [String]
      # @param work_item_ref [String, nil] ignored; keystrokes carry no metadata
      # @return [void]
      # @raise [RuntimeError] when tmux reports failure
      def deliver(session_id:, message:, **)
        send_keys!(session_id, message)
      end

      # No-op: panes are owned by the operator, not this adapter.
      #
      # @return [nil]
      def end_session(**)
        nil
      end

      # Confirms the work item's tmux target is among the live panes.
      #
      # @param work_item_id [String]
      # @return [String, nil] the tmux target, or nil if no such pane exists
      def active_session(work_item_id:)
        work_item = @work_item_repo.find(work_item_id)
        target = work_item&.workspace_name
        return nil if target.nil? || target.empty?

        out, status = run_command(["tmux", "list-panes", "-a", "-F",
                                   "\#{session_name}:\#{window_name}.\#{pane_index}"])
        return nil unless status.success?

        out.split("\n").include?(target) ? target : nil
      end

      # Returns all currently active tmux pane identifiers.
      #
      # @return [Array<String>] pane targets of the form `session:window.pane`
      def list_all_panes
        out, status = run_command(["tmux", "list-panes", "-a", "-F",
                                   "\#{session_name}:\#{window_name}.\#{pane_index}"])
        return [] unless status.success?

        out.split("\n").reject(&:empty?)
      end

      # Delivers a message to a specific pane of an already-running tmux session.
      #
      # Domain pane indices are 1-based; tmux pane indices are 0-based.
      # Domain pane 1 → tmux pane 0 (the first pane in window 0).
      #
      # @param workspace_name [String] tmux session name
      # @param pane_index [Integer] 1-based domain pane index
      # @param message [String]
      # @return [void]
      # @raise [Ports::AgentSession::PaneNotFoundError] when the pane does not exist
      # @raise [RuntimeError] when tmux send-keys reports failure
      def deliver_to_pane(workspace_name:, pane_index:, message:)
        # Domain pane indices are 1-based; tmux pane indices are 0-based.
        # Subtract 1 to convert: domain pane 1 → tmux 0, domain pane 2 → tmux 1, etc.
        # Assumes tmux window base-index of 0 (the default). Users with base-index 1
        # in ~/.tmux.conf will see PaneNotFoundError.
        tmux_pane_index = pane_index - 1
        window_target   = "#{workspace_name}:0"

        out, status = run_command(["tmux", "list-panes", "-t", window_target, "-F", "\#{pane_index}"])
        existing_indices = status.success? ? out.split("\n").map(&:to_i) : []

        unless existing_indices.include?(tmux_pane_index)
          raise Ports::AgentSession::PaneNotFoundError,
                "pane #{pane_index} not found in session '#{workspace_name}' " \
                "(tmux window #{window_target} has panes: #{existing_indices.inspect})"
        end

        pane_target = "#{workspace_name}:0.#{tmux_pane_index}"
        send_keys!(pane_target, message)
      end

      private

      def run_command(cmd)
        Open3.capture2e(*cmd)
      end

      def send_keys!(target, message)
        keys = control_sequence?(message) ? [message] : [message, "Enter"]
        out, status = run_command(["tmux", "send-keys", "-t", target, *keys])
        raise "tmux send-keys failed: #{out}" unless status.success?

        # Multiline messages put Claude Code into multiline input mode, where the
        # trailing Enter above becomes just another newline. A second Enter is needed
        # to actually submit the prompt.
        return unless message.include?("\n")

        out, status = run_command(["tmux", "send-keys", "-t", target, "Enter"])
        raise "tmux send-keys failed (submit): #{out}" unless status.success?
      end

      # Returns true for bare tmux control-key names (e.g. "C-c", "C-z").
      # These are sent directly without a trailing Enter — appending Enter after
      # an interrupt would immediately submit an empty prompt to the agent.
      def control_sequence?(message)
        message.match?(/\AC-[a-zA-Z]\z/)
      end
    end
  end
end
