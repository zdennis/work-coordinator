# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Application::UpdateAndRestart do
  let(:sender) { WorkCoordinator::Adapters::FakeMessageSender.new }

  # Records restart requests so the spec never execs a real process.
  let(:restart_coordinator) do
    Class.new do
      attr_reader :calls

      def initialize = @calls = []

      def call = calls << :called
    end.new
  end

  def build(git_runner)
    described_class.new(
      message_sender: sender,
      restart_coordinator: restart_coordinator,
      git_runner: git_runner
    )
  end

  def bodies = sender.sent_messages.map { |m| m[:body] }

  context "when the working tree is dirty" do
    let(:git_runner) { WorkCoordinator::Adapters::FakeGitRunner.new(dirty: true) }

    it "reports the local changes without pulling or restarting" do
      build(git_runner).call

      expect(bodies).to eq(
        ["Cannot update: working tree has local changes. Commit or stash them, then try /update again."]
      )
      expect(git_runner).not_to be_pulled
      expect(restart_coordinator.calls).to be_empty
    end
  end

  context "when the pull fails" do
    let(:git_runner) do
      WorkCoordinator::Adapters::FakeGitRunner.new(pull_error: "could not resolve host github.com")
    end

    it "reports the git failure and does not restart" do
      build(git_runner).call

      expect(bodies).to eq(["Update failed: could not resolve host github.com"])
      expect(restart_coordinator.calls).to be_empty
    end
  end

  context "when a git call other than pull fails" do
    let(:git_runner) do
      Class.new(WorkCoordinator::Adapters::FakeGitRunner) do
        def current_sha = raise(WorkCoordinator::Ports::GitRunner::Error, "not a git repository")
      end.new
    end

    it "reports the git failure and does not restart" do
      build(git_runner).call

      expect(bodies).to eq(["Update failed: not a git repository"])
      expect(restart_coordinator.calls).to be_empty
    end
  end

  context "when the dirty check itself fails" do
    let(:git_runner) do
      Class.new(WorkCoordinator::Adapters::FakeGitRunner) do
        def dirty? = raise(WorkCoordinator::Ports::GitRunner::Error, "not a git repository")
      end.new
    end

    it "reports the git failure and does not restart" do
      build(git_runner).call

      expect(bodies).to eq(["Update failed: not a git repository"])
      expect(restart_coordinator.calls).to be_empty
    end
  end

  context "when there is exactly one new commit" do
    let(:git_runner) { WorkCoordinator::Adapters::FakeGitRunner.new(commits_since: 1, sha: "def5678") }

    it "uses the singular noun" do
      build(git_runner).call

      expect(bodies).to eq(["Updated: 1 commit, now at def5678"])
    end
  end

  context "when there are no new commits" do
    let(:git_runner) { WorkCoordinator::Adapters::FakeGitRunner.new(commits_since: 0, sha: "abc1234") }

    it "reports being up to date and restarts" do
      build(git_runner).call

      expect(bodies).to eq(["Already up to date at abc1234"])
      expect(restart_coordinator.calls).to eq([:called])
    end
  end

  context "when there are new commits without a tag" do
    let(:git_runner) { WorkCoordinator::Adapters::FakeGitRunner.new(commits_since: 3, sha: "def5678") }

    it "reports the count and sha with no tag segment, then restarts" do
      build(git_runner).call

      expect(bodies).to eq(["Updated: 3 commits, now at def5678"])
      expect(restart_coordinator.calls).to eq([:called])
    end
  end

  context "when there are new commits at a tagged sha" do
    let(:git_runner) do
      WorkCoordinator::Adapters::FakeGitRunner.new(commits_since: 2, sha: "def5678", tag: "v1.2.3")
    end

    it "appends the tag to the report and restarts" do
      build(git_runner).call

      expect(bodies).to eq(["Updated: 2 commits, now at def5678 (tag: v1.2.3)"])
      expect(restart_coordinator.calls).to eq([:called])
    end
  end

  it "sends the update message to the human with no conversation" do
    build(WorkCoordinator::Adapters::FakeGitRunner.new(commits_since: 1)).call

    expect(sender.sent_messages).to eq(
      [{ to: nil, body: "Updated: 1 commit, now at abc1234", conversation_id: nil }]
    )
  end
end
