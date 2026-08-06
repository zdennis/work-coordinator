#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/adapters/socket_message_receiver"
require "work_coordinator/adapters/socket_message_sender"

include OutputHelpers

SOCKET_PATH = "/tmp/work-coordinator-verify-#{Process.pid}.sock".freeze

section "SocketMessageReceiver + SocketMessageSender — local transport"

received_messages = []
receiver = WorkCoordinator::Adapters::SocketMessageReceiver.new(socket_path: SOCKET_PATH)
sender   = WorkCoordinator::Adapters::SocketMessageSender.new(socket_path: SOCKET_PATH)

thread = Thread.new do
  receiver.start { |msg| received_messages << msg }
end

sleep 0.1 # let the server bind

# Normal message with ref
sender.send_message(body: "MS-123 yes update it")
sleep 0.05

# Body-only line (no spaces, so no ref token)
sender.send_message(body: "bodyonlynospaces")
sleep 0.05

receiver.stop
thread.join(2)

raise "expected 2 messages, got #{received_messages.length}" unless received_messages.length == 2

msg1 = received_messages[0]
raise "ref mismatch: #{msg1[:work_item_ref].inspect}" unless msg1[:work_item_ref] == "MS-123"
raise "body mismatch: #{msg1[:body].inspect}" unless msg1[:body] == "yes update it"
raise "missing received_at" unless msg1[:received_at]

pass "parsed ref and body correctly"
pass "received_at is set"

msg2 = received_messages[1]
raise "nil-ref message should have nil ref: #{msg2[:work_item_ref].inspect}" unless msg2[:work_item_ref].nil?
raise "nil-ref body mismatch: #{msg2[:body].inspect}" unless msg2[:body] == "bodyonlynospaces"

pass "body-only line yields nil ref without crashing"

section "Teardown"
require "fileutils"
FileUtils.rm_f(SOCKET_PATH)
pass "socket file cleaned up"
