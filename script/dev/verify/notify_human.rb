#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/domain/work_item"
require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_message_sender"
require "work_coordinator/application/event_store"
require "work_coordinator/application/register_work_item"
require "work_coordinator/application/notify_human"

include OutputHelpers

repo = WorkCoordinator::Adapters::InMemoryWorkItemRepository.new
message_sender = WorkCoordinator::Adapters::FakeMessageSender.new
event_store = WorkCoordinator::Application::InMemoryEventStore.new

section "Step 1 — Register work item GE-456"

register = WorkCoordinator::Application::RegisterWorkItem.new(
  work_item_repo: repo,
  event_store: event_store
)

work_item = register.call(title: "Kafka fixture check", kind: :jira, external_reference: "GE-456")
pass "Registered work item id=#{work_item.id} ref=#{work_item.external_reference}"

section "Step 2 — Notify human"

notify = WorkCoordinator::Application::NotifyHuman.new(
  message_sender: message_sender,
  work_item_repo: repo,
  event_store: event_store
)

notify.call(work_item_id: work_item.id, body: "Should I update the Kafka fixture?")
pass "NotifyHuman#call completed"

section "Step 3 — Assert FakeMessageSender received message with [GE-456] prefix"

messages = message_sender.sent_messages
raise "expected 1 sent message, got #{messages.length}" unless messages.length == 1

body = messages.first[:body]
raise "expected body to start with '[GE-456]', got: #{body}" unless body.start_with?("[GE-456]")

pass "Message received with [GE-456] prefix"

section "Step 4 — Verify message format"

expected_body = "[GE-456] Should I update the Kafka fixture?\nReply: GE-456 <your response>"
unless body == expected_body
  raise "Message format mismatch.\nExpected: #{expected_body.inspect}\nGot:      #{body.inspect}"
end

pass "Message format correct"

section "Step 5 — Assert agent.question_asked event recorded"

events = event_store.all
question_events = events.select { |e| e.type == "agent.question_asked" }
raise "expected 1 agent.question_asked event, got #{question_events.length}" unless question_events.length == 1

pass "Event 'agent.question_asked' recorded"

section "Step 6 — Assert work item transitioned to waiting_for_human"

updated = repo.find(work_item.id)
raise "expected state :waiting_for_human, got #{updated.state}" unless updated.state == :waiting_for_human

pass "Work item state is :waiting_for_human"
