# frozen_string_literal: true

require "spec_helper"

# Drives the whole self-restart path with real collaborators — inbound message,
# AiCommandReceiver, RestartCoordinator, UpdateAndRestart — and fakes only at
# the process boundary: exec, sleep, exit, git, and the message transports.
RSpec.describe "self-restart end to end" do
  let(:sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:state_repo) { WorkCoordinator::Adapters::InMemoryRestartStateRepository.new }
  let(:argv) { ["bin/work-coordinator", "run"] }
  let(:env) { { "WC_RECIPIENT" => "+15555550100" } }

  let(:exec_calls) { [] }
  let(:sleep_calls) { [] }
  let(:exit_calls) { [] }
  let(:before_exec_calls) { [] }

  # Overridden per narrative; the default stands in for a successful exec, which
  # never returns in production but must return here so the spec can continue.
  let(:exec_fn) { ->(env, *cmd) { exec_calls << [env, *cmd] } }

  let(:restart_coordinator) do
    WorkCoordinator::Application::RestartCoordinator.new(
      message_sender: sender,
      restart_state_repo: state_repo,
      argv: argv,
      env: env,
      max_attempts: 3,
      exec_fn: exec_fn,
      sleep_fn: ->(secs) { sleep_calls << secs },
      before_exec: -> { before_exec_calls << :called },
      exit_fn: ->(code) { exit_calls << code }
    )
  end

  let(:git_runner) { WorkCoordinator::Adapters::FakeGitRunner.new }

  let(:update_and_restart) do
    WorkCoordinator::Application::UpdateAndRestart.new(
      message_sender: sender,
      restart_coordinator: restart_coordinator,
      git_runner: git_runner
    )
  end

  let(:inner) { WorkCoordinator::Adapters::FakeMessageReceiver.new }

  let(:receiver) do
    WorkCoordinator::Adapters::AiCommandReceiver.new(
      inner: inner,
      ai_command_handler: ->(_msg) { raise "unexpected fallthrough to the AI command handler" },
      deliver_to_main_session: ->(**) { raise "unexpected delivery to the main session" },
      restart_coordinator: restart_coordinator,
      update_and_restart: update_and_restart
    )
  end

  def bodies = sender.sent_messages.map { |m| m[:body] }

  def deliver(verb)
    inner.stub_message(work_item_ref: verb, body: "")
    receiver.start { |_msg| raise "unexpected routing to a work item" }
  end

  describe "a successful restart" do
    it "acks, execs, and announces success on the other side of the process boundary" do
      deliver("restart")

      expect(bodies).to eq(["Restarting..."])
      expect(exec_calls).to eq([[env, *argv]])
      expect(before_exec_calls.size).to eq(1)
      expect(state_repo.load.attempt).to eq(0)

      # The process boundary: a fresh coordinator over the same repository, as a
      # rebooted daemon would build from persisted state.
      rebooted = WorkCoordinator::Application::RestartCoordinator.new(
        message_sender: sender,
        restart_state_repo: state_repo,
        argv: argv,
        env: env,
        before_exec: -> { before_exec_calls << :called }
      )
      rebooted.announce_boot!

      expect(bodies).to eq(["Restarting...", "Restarted successfully."])
      expect(state_repo.load).to be_nil
    end
  end

  describe "a restart whose exec never succeeds" do
    let(:exec_fn) do
      lambda do |_env, *_cmd|
        exec_calls << :attempted
        # Bare, so the message is exactly the strerror text the real exec would give.
        raise Errno::ENOENT
      end
    end

    it "retries three times, gives up, and leaves no state behind" do
      deliver("restart")

      expect(bodies).to eq(
        [
          "Restarting...",
          "Restart failed: No such file or directory. Will retry 3 more times.",
          "Restart failed: No such file or directory. Will retry 2 more times.",
          "Restart failed: No such file or directory. Will retry 1 more times.",
          "Restart failed after 3 attempts: No such file or directory. " \
          "Coordinator is exiting; restart it manually."
        ]
      )
      expect(exec_calls.size).to eq(4)
      expect(sleep_calls).to eq([5, 5, 5])
      expect(exit_calls).to eq([1])
      expect(state_repo.load).to be_nil
    end
  end

  describe "a successful update" do
    let(:git_runner) do
      WorkCoordinator::Adapters::FakeGitRunner.new(
        dirty: false, sha: "abc1234", commits_since: 3, tag: "v1.0.0"
      )
    end

    it "reports the delta before acking the restart" do
      deliver("update")

      expect(bodies).to eq(
        [
          "Updated: 3 commits, now at abc1234 (tag: v1.0.0)",
          "Restarting..."
        ]
      )
      expect(git_runner).to be_pulled
      expect(exec_calls).to eq([[env, *argv]])
    end
  end
end
