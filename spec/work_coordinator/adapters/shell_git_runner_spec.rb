# frozen_string_literal: true

require "spec_helper"

RSpec.describe WorkCoordinator::Adapters::ShellGitRunner do
  exit_status = Struct.new(:success?)

  define_method(:runner_returning) do |stdout: "", stderr: "", success: true|
    commands = []
    runner = lambda do |command|
      commands << command
      [stdout, stderr, exit_status.new(success)]
    end
    [runner, commands]
  end

  let(:dir) { "/checkout" }

  describe "#dirty?" do
    it "runs git status --porcelain and is false on empty output" do
      runner, commands = runner_returning(stdout: "\n")

      expect(described_class.new(dir: dir, runner: runner).dirty?).to be(false)
      expect(commands).to eq(["git -C /checkout status --porcelain"])
    end

    it "is true when the porcelain output is non-empty" do
      runner, = runner_returning(stdout: " M lib/foo.rb\n")

      expect(described_class.new(dir: dir, runner: runner).dirty?).to be(true)
    end
  end

  describe "#pull" do
    it "runs git pull" do
      runner, commands = runner_returning(stdout: "Already up to date.\n")

      described_class.new(dir: dir, runner: runner).pull

      expect(commands).to eq(["git -C /checkout pull"])
    end

    it "raises the port's error carrying stderr when git exits non-zero" do
      runner, = runner_returning(stderr: "fatal: no upstream\n", success: false)

      expect { described_class.new(dir: dir, runner: runner).pull }
        .to raise_error(WorkCoordinator::Ports::GitRunner::Error, "fatal: no upstream")
    end
  end

  describe "#commits_since" do
    it "counts commits from the given sha and returns an Integer" do
      runner, commands = runner_returning(stdout: "7\n")

      expect(described_class.new(dir: dir, runner: runner).commits_since("abc1234")).to eq(7)
      expect(commands).to eq(["git -C /checkout rev-list abc1234..HEAD --count"])
    end
  end

  describe "#current_sha" do
    it "returns the abbreviated sha" do
      runner, commands = runner_returning(stdout: "deadbee\n")

      expect(described_class.new(dir: dir, runner: runner).current_sha).to eq("deadbee")
      expect(commands).to eq(["git -C /checkout rev-parse --short HEAD"])
    end
  end

  describe "#current_tag" do
    it "returns the exact tag at HEAD" do
      runner, commands = runner_returning(stdout: "v1.2.0\n")

      expect(described_class.new(dir: dir, runner: runner).current_tag).to eq("v1.2.0")
      expect(commands).to eq(["git -C /checkout describe --tags --exact-match HEAD"])
    end

    it "returns nil when HEAD carries no tag" do
      runner, = runner_returning(stderr: "fatal: no tag exactly matches\n", success: false)

      expect(described_class.new(dir: dir, runner: runner).current_tag).to be_nil
    end
  end

  describe "the default directory" do
    it "is the coordinator's own checkout, not the process working directory" do
      runner, commands = runner_returning(stdout: "deadbee\n")
      root = File.expand_path("../../..", __dir__)

      described_class.new(runner: runner).current_sha

      expect(commands.first).to eq("git -C #{root} rev-parse --short HEAD")
    end
  end
end
