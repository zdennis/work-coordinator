#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/adapters/tmux_agent_session"

include OutputHelpers

TmuxAgentSession = WorkCoordinator::Adapters::TmuxAgentSession

FakeStatus = Struct.new(:ok) do
  def success? = ok
end

FakeRepo = Struct.new(:items) do
  def find(id) = items[id]
end

FakeWorkItem = Struct.new(:id, :tmux_target)

# Subclass that captures commands instead of running them
class TestTmuxAgentSession < TmuxAgentSession
  attr_reader :commands

  def initialize(work_item_repo:)
    super
    @commands = []
    @command_results = {}
  end

  def stub_command(cmd_pattern, output:, success: true)
    @command_results[cmd_pattern] = [output, FakeStatus.new(success)]
  end

  private

  def run_command(cmd)
    @commands << cmd
    key = @command_results.keys.find { |k| cmd.join(" ").include?(k) }
    key ? @command_results[key] : ["", FakeStatus.new(true)]
  end
end

# rubocop:disable Style/OneClassPerFile
class FailingSession < TestTmuxAgentSession
  private

  def run_command(cmd)
    @commands << cmd
    ["error output", FakeStatus.new(false)]
  end
end
# rubocop:enable Style/OneClassPerFile

section "start_session — raises without tmux_target"

repo = FakeRepo.new({ "wi-1" => FakeWorkItem.new("wi-1", nil) })
adapter = TestTmuxAgentSession.new(work_item_repo: repo)

begin
  adapter.start_session(work_item_id: "wi-1")
  raise "expected ArgumentError but none was raised"
rescue ArgumentError => e
  pass "raises ArgumentError when work item has no tmux_target (#{e.message})"
end

section "start_session — returns tmux_target as session_id"

repo2 = FakeRepo.new({ "wi-2" => FakeWorkItem.new("wi-2", "my-service:claude.0") })
adapter2 = TestTmuxAgentSession.new(work_item_repo: repo2)
session_id = adapter2.start_session(work_item_id: "wi-2")
raise "expected 'my-service:claude.0', got #{session_id.inspect}" unless session_id == "my-service:claude.0"

pass "start_session returns tmux_target string as session_id"

section "deliver — calls correct tmux command"

adapter2.deliver(session_id: "my-service:claude.0", message: "hello world")
cmd = adapter2.commands.last
raise "expected tmux send-keys command" unless cmd[0..2] == ["tmux", "send-keys", "-t"]
raise "expected session target in command" unless cmd[3] == "my-service:claude.0"
raise "expected 'Enter' at end" unless cmd.last == "Enter"

pass "deliver calls tmux send-keys with correct target and Enter"

section "deliver — raises on non-zero exit"

repo3 = FakeRepo.new({ "wi-3" => FakeWorkItem.new("wi-3", "session:win.0") })
failing = FailingSession.new(work_item_repo: repo3)

begin
  failing.deliver(session_id: "session:win.0", message: "boom")
  raise "expected RuntimeError but none was raised"
rescue RuntimeError => e
  pass "deliver raises RuntimeError on non-zero exit (#{e.message})"
end

section "active_session — returns target when pane exists"

repo4 = FakeRepo.new({ "wi-4" => FakeWorkItem.new("wi-4", "my-service:claude.0") })
adapter4 = TestTmuxAgentSession.new(work_item_repo: repo4)
adapter4.stub_command("list-panes", output: "my-service:claude.0\nother:1.0")

result = adapter4.active_session(work_item_id: "wi-4")
raise "expected 'my-service:claude.0', got #{result.inspect}" unless result == "my-service:claude.0"

pass "active_session returns target when pane is listed"

section "active_session — returns nil when pane missing"

repo5 = FakeRepo.new({ "wi-5" => FakeWorkItem.new("wi-5", "my-service:claude.0") })
adapter5 = TestTmuxAgentSession.new(work_item_repo: repo5)
adapter5.stub_command("list-panes", output: "other:1.0\nanother:2.1")

result5 = adapter5.active_session(work_item_id: "wi-5")
raise "expected nil, got #{result5.inspect}" unless result5.nil?

pass "active_session returns nil when pane not found"

section "active_session — handles missing tmux_target gracefully"

repo6 = FakeRepo.new({ "wi-6" => FakeWorkItem.new("wi-6", nil) })
adapter6 = TestTmuxAgentSession.new(work_item_repo: repo6)

result6 = adapter6.active_session(work_item_id: "wi-6")
raise "expected nil for missing target, got #{result6.inspect}" unless result6.nil?

pass "active_session returns nil when work item has no tmux_target"

section "end_session — no-op, returns nil"

ret = adapter2.end_session(session_id: "my-service:claude.0")
raise "expected nil, got #{ret.inspect}" unless ret.nil?

pass "end_session returns nil"
