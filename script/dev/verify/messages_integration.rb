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
sender.send_message(body: "ai: MS-123 yes do it")
expected_cmd = ["send-message", "--message", "ai: MS-123 yes do it"]
unless sender.recorded_commands.last == expected_cmd
  raise "AppleScriptMessageSender: send_message calls correct command — got #{sender.recorded_commands.last.inspect}"
end

pass "AppleScriptMessageSender: send_message calls correct command"

error_sender = TestableMessageSender.new(send_message_bin: "send-message")
error_sender.stub_result("something broke", success: false)
begin
  error_sender.send_message(body: "ai: MS-123 yes do it")
  raise "AppleScriptMessageSender: raises RuntimeError on non-zero exit"
rescue RuntimeError => e
  unless e.message.include?("send-message failed")
    raise "AppleScriptMessageSender: RuntimeError message unexpected — #{e.message}"
  end

  pass "AppleScriptMessageSender: raises RuntimeError on non-zero exit"
end

# Section B — MessagesInboxPoller

db_path = File.join(Dir.tmpdir, "test_messages_#{Process.pid}.db")
begin
  db = SQLite3::Database.new(db_path)
  db.execute(<<~SQL)
    CREATE TABLE message (
      rowid INTEGER PRIMARY KEY,
      text TEXT,
      date INTEGER,
      is_from_me INTEGER
    )
  SQL
  db.execute("INSERT INTO message VALUES (1, 'ai: MS-123 yes update it', 1000, 0)")
  db.execute("INSERT INTO message VALUES (2, 'hello world', 1001, 0)")
  db.execute("INSERT INTO message VALUES (3, 'ai: MS-456 check status', 1002, 1)")
  db.execute("INSERT INTO message VALUES (4, 'ai: MS-456 run tests', 1003, 0)")
  db.close

  poller = WorkCoordinator::Adapters::MessagesInboxPoller.new(db_path: db_path)
  poller.instance_variable_set(:@last_date, 0)

  messages = []
  poller.send(:poll_once) { |m| messages << m }

  raise "MessagesInboxPoller: expected 2 messages, got #{messages.size}" unless messages.size == 2

  pass "MessagesInboxPoller: yields 2 matching messages"

  first = messages[0]
  unless first[:work_item_ref] == "MS-123" && first[:body] == "yes update it"
    raise "MessagesInboxPoller: first message — #{first.inspect}"
  end

  pass "MessagesInboxPoller: first message parsed correctly"

  second = messages[1]
  unless second[:work_item_ref] == "MS-456" && second[:body] == "run tests"
    raise "MessagesInboxPoller: second message — #{second.inspect}"
  end

  pass "MessagesInboxPoller: second message parsed correctly"
ensure
  FileUtils.rm_f(db_path)
end
