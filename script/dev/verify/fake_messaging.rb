#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/adapters/fake_message_sender"
require "work_coordinator/adapters/fake_message_receiver"

include OutputHelpers

FakeMessageSender = WorkCoordinator::Adapters::FakeMessageSender
FakeMessageReceiver = WorkCoordinator::Adapters::FakeMessageReceiver

section "FakeMessageSender — send_message"

sender = FakeMessageSender.new
raise "sent_messages should be empty initially" unless sender.sent_messages.empty?

sender.send_message(to: "agent-1", body: "Hello")
sender.send_message(to: "agent-2", body: "World", conversation_id: "conv-99")

msgs = sender.sent_messages
raise "expected 2 sent messages, got #{msgs.length}" unless msgs.length == 2
raise "first message wrong: #{msgs[0].inspect}" unless msgs[0] == { to: "agent-1", body: "Hello", conversation_id: nil }

expected2 = { to: "agent-2", body: "World", conversation_id: "conv-99" }
raise "second message wrong: #{msgs[1].inspect}" unless msgs[1] == expected2

pass "send_message appends to sent_messages"
pass "sent_messages returns all messages in order"

section "FakeMessageReceiver — stub_message and receive_messages"

receiver = FakeMessageReceiver.new
raise "receive_messages should return empty array initially" unless receiver.receive_messages.empty?

receiver.stub_message(work_item_ref: "wi-1", body: "First reply")
receiver.stub_message(work_item_ref: "wi-2", body: "Second reply")

received = receiver.receive_messages
raise "expected 2 received messages, got #{received.length}" unless received.length == 2
raise "first received wrong work_item_ref" unless received[0][:work_item_ref] == "wi-1"
raise "first received wrong body" unless received[0][:body] == "First reply"
raise "first received missing received_at" unless received[0][:received_at]
raise "second received wrong work_item_ref" unless received[1][:work_item_ref] == "wi-2"

pass "stub_message queues messages for receive_messages"
pass "receive_messages returns hashes with work_item_ref, body, received_at"

section "Round-trip — sender sends, receiver echoes back"

sender2 = FakeMessageSender.new
receiver2 = FakeMessageReceiver.new

sender2.send_message(to: "coordinator", body: "Task done")
receiver2.stub_message(work_item_ref: "wi-42", body: "Task done")

out = sender2.sent_messages.last
echo = receiver2.receive_messages.last

raise "sent body mismatch" unless out[:body] == "Task done"
raise "received body mismatch" unless echo[:body] == "Task done"

pass "round-trip: sender and receiver exchange matching message body"
