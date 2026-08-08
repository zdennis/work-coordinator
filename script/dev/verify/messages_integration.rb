#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "tmpdir"

FakeStatus = Struct.new(:success?)
require "sqlite3"
require "work_coordinator/adapters/apple_script_message_sender"
require "work_coordinator/adapters/messages_inbox_poller"

include OutputHelpers

# Section A — AppleScriptMessageSender

class TestableMessageSender < WorkCoordinator::Adapters::AppleScriptMessageSender
  attr_reader :recorded_commands

  def initialize(...)
    super
    @recorded_commands = []
    @next_result = nil
  end

  def stub_result(output, success:)
    @next_result = [output, FakeStatus.new(success)]
  end

  protected

  def run_command(cmd)
    @recorded_commands << cmd
    @next_result || ["ok", FakeStatus.new(true)]
  end
end

sender = TestableMessageSender.new(send_message_bin: "send-message")
sender.stub_result("ok", success: true)
sender.send_message(body: "ai: GE-123 yes do it")
expected_cmd = ["send-message", "--message", "ai: GE-123 yes do it"]
unless sender.recorded_commands.last == expected_cmd
  raise "AppleScriptMessageSender: send_message calls correct command — got #{sender.recorded_commands.last.inspect}"
end

pass "AppleScriptMessageSender: send_message calls correct command"

error_sender = TestableMessageSender.new(send_message_bin: "send-message")
error_sender.stub_result("something broke", success: false)
begin
  error_sender.send_message(body: "ai: GE-123 yes do it")
  raise "AppleScriptMessageSender: raises RuntimeError on non-zero exit"
rescue RuntimeError => e
  unless e.message.include?("send-message failed")
    raise "AppleScriptMessageSender: RuntimeError message unexpected — #{e.message}"
  end

  pass "AppleScriptMessageSender: raises RuntimeError on non-zero exit"
end

# Section B — MessagesInboxPoller

SeenRepo = Struct.new(:seen_guids) do
  def seen?(guid) = seen_guids.include?(guid)
  def record(guid) = seen_guids << guid
end

db_path = File.join(Dir.tmpdir, "test_messages_#{Process.pid}.db")
begin
  mac_epoch = Time.utc(2001, 1, 1).to_i
  base_mac = ((Time.now.to_f - mac_epoch - 3600) * 1_000_000_000).to_i

  db = SQLite3::Database.new(db_path)
  db.execute(<<~SQL)
    CREATE TABLE message (
      rowid INTEGER PRIMARY KEY,
      text TEXT,
      date INTEGER,
      guid TEXT,
      is_from_me INTEGER
    )
  SQL
  insert_sql = "INSERT INTO message (rowid, text, date, guid, is_from_me) VALUES (?, ?, ?, ?, ?)"
  db.execute(insert_sql, [1, "ai: GE-123 yes update it", base_mac, "msg-guid-1", 0])
  db.execute(insert_sql, [2, "hello world", base_mac + 1_000_000_000, "msg-guid-2", 0])
  db.execute(insert_sql, [3, "ai: GE-456 check status", base_mac + 2_000_000_000, "msg-guid-3", 1])
  db.execute(insert_sql, [4, "ai: GE-456 run tests", base_mac + 3_000_000_000, "msg-guid-4", 0])
  db.close

  repo = SeenRepo.new([])
  poller = WorkCoordinator::Adapters::MessagesInboxPoller.new(inbound_message_repo: repo, db_path: db_path)
  poller.instance_variable_set(:@last_date, 0)

  messages = []
  poller.send(:poll_once) { |m| messages << m }

  raise "MessagesInboxPoller: expected 2 messages, got #{messages.size}" unless messages.size == 2

  pass "MessagesInboxPoller: yields 2 matching messages"

  first = messages[0]
  unless first[:work_item_ref] == "GE-123" && first[:body] == "yes update it"
    raise "MessagesInboxPoller: first message — #{first.inspect}"
  end

  pass "MessagesInboxPoller: first message parsed correctly"

  second = messages[1]
  unless second[:work_item_ref] == "GE-456" && second[:body] == "run tests"
    raise "MessagesInboxPoller: second message — #{second.inspect}"
  end

  pass "MessagesInboxPoller: second message parsed correctly"

  unless first[:received_at].is_a?(Time) && second[:received_at].is_a?(Time)
    raise "MessagesInboxPoller: received_at should be a Time — #{first[:received_at].inspect}"
  end

  pass "MessagesInboxPoller: received_at is a Time"

  dedup_repo = SeenRepo.new(["msg-guid-1"])
  dedup_poller = WorkCoordinator::Adapters::MessagesInboxPoller.new(inbound_message_repo: dedup_repo, db_path: db_path)
  dedup_poller.instance_variable_set(:@last_date, 0)

  deduped = []
  dedup_poller.send(:poll_once) { |m| deduped << m }

  unless deduped.size == 1 && deduped[0][:guid] == "msg-guid-4"
    raise "MessagesInboxPoller: expected only unseen message, got #{deduped.map { _1[:guid] }.inspect}"
  end

  pass "MessagesInboxPoller: skips already-seen guids"
ensure
  FileUtils.rm_f(db_path)
end
