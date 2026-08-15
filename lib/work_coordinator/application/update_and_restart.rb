# frozen_string_literal: true

require "work_coordinator/ports/git_runner"

module WorkCoordinator
  module Application
    # Pulls the coordinator's own checkout, reports what changed, and restarts.
    #
    # A dirty tree or a failed pull short-circuits: the human hears why and the
    # process keeps running the code it already has.
    class UpdateAndRestart
      # @param message_sender [Ports::MessageSender]
      # @param restart_coordinator [RestartCoordinator]
      # @param git_runner [Ports::GitRunner]
      def initialize(message_sender:, restart_coordinator:, git_runner:)
        @message_sender = message_sender
        @restart_coordinator = restart_coordinator
        @git_runner = git_runner
      end

      # @return [void]
      def call
        begin
          if @git_runner.dirty?
            return notify("Cannot update: working tree has local changes. " \
                          "Commit or stash them, then try /update again.")
          end

          before = @git_runner.current_sha
          @git_runner.pull
          notify(report(@git_runner.commits_since(before), @git_runner.current_sha))
        rescue Ports::GitRunner::Error => e
          return notify("Update failed: #{e.message}")
        end

        @restart_coordinator.call
      end

      private

      def report(count, sha)
        return "Already up to date at #{sha}" if count.zero?

        body = "Updated: #{count} #{count == 1 ? 'commit' : 'commits'}, now at #{sha}"
        tag = @git_runner.current_tag
        tag ? "#{body} (tag: #{tag})" : body
      end

      def notify(body)
        @message_sender.send_message(to: nil, body: body, conversation_id: nil)
      end
    end
  end
end
