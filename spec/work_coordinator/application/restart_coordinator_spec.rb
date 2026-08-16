# frozen_string_literal: true

require "work_coordinator"

RSpec.describe WorkCoordinator::Application::RestartCoordinator do
  let(:sender) { WorkCoordinator::Adapters::FakeMessageSender.new }
  let(:repo) { WorkCoordinator::Adapters::InMemoryRestartStateRepository.new }
  let(:argv) { ["/usr/bin/work-coordinator", "run"] }
  let(:env) { { "PATH" => "/usr/bin" } }

  # Recorded invocations of every injected function, keyed by name.
  let(:calls) { Hash.new { |h, k| h[k] = [] } }

  # Number of leading exec attempts that should raise; the rest succeed.
  let(:failures) { 0 }

  let(:coordinator) do
    described_class.new(
      message_sender: sender,
      restart_state_repo: repo,
      argv: argv,
      env: env,
      max_attempts: 3,
      exec_fn: lambda { |e, *cmd|
        calls[:exec] << [e, *cmd]
        calls[:state] << repo.load
        calls[:messages] << sender.sent_messages.map { |m| m[:body] }
        raise Errno::ENOENT, "work-coordinator" if failures == :always || calls[:exec].size <= failures

        :execed
      },
      sleep_fn: ->(secs) { calls[:sleep] << secs },
      before_exec: lambda {
        calls[:before_exec] << :called
        calls[:order] << :before_exec
      },
      notify_restart_fn: lambda {
        calls[:notify_restart] << :called
        calls[:order] << :notify
      },
      exit_fn: ->(code) { calls[:exit] << code }
    )
  end

  def bodies
    sender.sent_messages.map { |m| m[:body] }
  end

  describe "#call on the happy path" do
    it "execs once with the env first and argv after" do
      coordinator.call

      expect(calls[:exec]).to eq([[env, "/usr/bin/work-coordinator", "run"]])
    end

    it "acknowledges before exec and sends nothing else" do
      coordinator.call

      expect(bodies).to eq(["Restarting..."])
    end

    it "persists attempt 0 before exec" do
      coordinator.call

      expect(calls[:state].first.attempt).to eq(0)
    end

    it "sends the acknowledgement before exec" do
      coordinator.call

      expect(calls[:messages].first).to eq(["Restarting..."])
    end

    it "runs before_exec exactly once" do
      coordinator.call

      expect(calls[:before_exec].size).to eq(1)
    end

    it "runs notify_restart_fn exactly once" do
      coordinator.call

      expect(calls[:notify_restart].size).to eq(1)
    end

    it "notifies the workspace agents before tearing down the database connection" do
      coordinator.call

      expect(calls[:order]).to eq(%i[notify before_exec])
    end

    it "does not sleep or exit" do
      coordinator.call

      expect(calls[:sleep]).to be_empty
      expect(calls[:exit]).to be_empty
    end
  end

  describe "#call when the first exec fails and a retry succeeds" do
    let(:failures) { 2 }

    it "retries until exec succeeds" do
      coordinator.call

      expect(calls[:exec].size).to eq(3)
    end

    it "sleeps five seconds before each retry" do
      coordinator.call

      expect(calls[:sleep]).to eq([5, 5])
    end

    it "sends one failure message per failed attempt" do
      coordinator.call

      expect(bodies).to eq(
        [
          "Restarting...",
          "Restart failed: No such file or directory - work-coordinator. Will retry 3 more times.",
          "Restart failed: No such file or directory - work-coordinator. Will retry 2 more times."
        ]
      )
    end

    it "still runs before_exec only once" do
      coordinator.call

      expect(calls[:before_exec].size).to eq(1)
    end

    it "leaves the state row behind for the new process to announce" do
      coordinator.call

      expect(repo.load.attempt).to eq(2)
    end
  end

  describe "#call when every exec fails" do
    let(:failures) { :always }

    it "sends the exhaustion transcript" do
      coordinator.call

      expect(bodies).to eq(
        [
          "Restarting...",
          "Restart failed: No such file or directory - work-coordinator. Will retry 3 more times.",
          "Restart failed: No such file or directory - work-coordinator. Will retry 2 more times.",
          "Restart failed: No such file or directory - work-coordinator. Will retry 1 more times.",
          "Restart failed after 3 attempts: No such file or directory - work-coordinator. " \
          "Coordinator is exiting; restart it manually."
        ]
      )
    end

    it "stops after max_attempts retries rather than looping forever" do
      coordinator.call

      expect(calls[:exec].size).to eq(4)
      expect(calls[:sleep]).to eq([5, 5, 5])
    end

    it "clears the state row so the next manual start stays quiet" do
      coordinator.call

      expect(repo.load).to be_nil
    end

    it "exits non-zero through the injected exit function" do
      coordinator.call

      expect(calls[:exit]).to eq([1])
    end
  end

  describe "#call with a stale state row" do
    it "resets the attempt counter even when a prior row shows progress" do
      repo.save(attempt: 2)

      coordinator.call

      expect(calls[:state].first.attempt).to eq(0)
    end
  end

  describe "#announce_boot!" do
    it "announces success and clears the row when a restart is in flight" do
      repo.save(attempt: 0)

      coordinator.announce_boot!

      expect(bodies).to eq(["Restarted successfully."])
      expect(repo.load).to be_nil
    end

    it "stays silent when no restart was recorded" do
      coordinator.announce_boot!

      expect(sender.sent_messages).to be_empty
    end
  end
end
