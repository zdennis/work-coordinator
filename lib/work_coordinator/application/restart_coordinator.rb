# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Replaces the running coordinator process with a fresh one via `exec`,
    # keeping retry bookkeeping in a repository so it survives the hand-off.
    #
    # Every dangerous operation — exec, sleep, exit, and the pre-exec teardown —
    # arrives as an injected lambda so specs never touch the real process.
    class RestartCoordinator
      RETRY_DELAY_SECONDS = 5

      # @param message_sender [Ports::MessageSender]
      # @param restart_state_repo [Ports::RestartStateRepository]
      # @param argv [Array<String>] the command to exec, program name first
      # @param env [Hash{String=>String}] environment for the new process
      # @param max_attempts [Integer] retries after the first exec fails
      # @param exec_fn [#call] receives `(env, *argv)`; never returns on success
      # @param sleep_fn [#call] receives the delay in seconds
      # @param before_exec [#call] teardown run once before the first exec
      # @param notify_restart_fn [#call] runs before the teardown, while the DB is still readable
      # @param exit_fn [#call] receives the exit status
      # @return [void]
      def initialize(message_sender:, restart_state_repo:, argv:, env:, before_exec:,
                     max_attempts: 3,
                     exec_fn: ->(env, *cmd) { Kernel.exec(env, *cmd) },
                     sleep_fn: ->(secs) { sleep(secs) },
                     notify_restart_fn: -> {},
                     exit_fn: ->(code) { Kernel.exit(code) })
        @message_sender = message_sender
        @restart_state_repo = restart_state_repo
        @argv = argv
        @env = env
        @max_attempts = max_attempts
        @exec_fn = exec_fn
        @sleep_fn = sleep_fn
        @before_exec = before_exec
        @notify_restart_fn = notify_restart_fn
        @exit_fn = exit_fn
      end

      # Persists restart state, acknowledges to the human, and execs. On failure
      # retries up to `max_attempts` times, announcing each attempt; when the
      # retries run out it clears the state row and exits non-zero.
      #
      # @return [void]
      def call
        attempt = 0
        @restart_state_repo.save(attempt: attempt)
        notify("Restarting...")

        @notify_restart_fn.call
        @before_exec.call
        reason = attempt_exec
        return unless reason

        retry_until_exhausted(attempt, reason)
      end

      # Announces a restart that made it all the way to a fresh boot, then drops
      # the bookkeeping. No-op when the process was not restarted.
      #
      # @return [void]
      def announce_boot!
        return unless @restart_state_repo.load

        begin
          notify("Restarted successfully.")
        rescue StandardError => e
          warn "announce_boot! failed: #{e.message}"
        end

        @restart_state_repo.clear
      end

      private

      # @return [String, nil] the failure reason, or nil when exec succeeded
      def attempt_exec
        @exec_fn.call(@env, *@argv)
        nil
      rescue SystemCallError, TypeError => e # exec's failure modes: bad path, bad argument shape
        e.message
      end

      def retry_until_exhausted(attempt, reason)
        last_reason = reason
        while attempt < @max_attempts
          attempt += 1
          @restart_state_repo.save(attempt: attempt)
          notify("Restart failed: #{last_reason}. Will retry #{@max_attempts - attempt + 1} more times.")
          @sleep_fn.call(RETRY_DELAY_SECONDS)

          reason = attempt_exec
          return unless reason

          last_reason = reason
        end

        exhausted(last_reason)
      end

      def exhausted(last_reason)
        notify("Restart failed after #{@max_attempts} attempts: #{last_reason}. " \
               "Coordinator is exiting; restart it manually.")
        @restart_state_repo.clear
        @exit_fn.call(1)
      end

      def notify(body)
        @message_sender.send_message(to: nil, body: body, conversation_id: nil)
      end
    end
  end
end
