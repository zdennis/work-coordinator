#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator"
require "work_coordinator/adapters/fake_message_sender"

include OutputHelpers

section "Boot Container with in-memory SQLite"
container = WorkCoordinator::Container.new(db_path: ":memory:")
pass "Container booted"

section "Step 1 — RegisterWorkItem"
work_item = container.register_work_item.call(
  title: "Fix Kafka fixture",
  kind: :jira,
  external_reference: "MS-123",
  repository: "acme-billing"
)
pass "work item id: #{work_item.id}"
pass "state: #{work_item.state}"
raise "expected :created state" unless work_item.state == :created

section "Step 2 — Verify created event recorded"
events = container.event_store.all_for(work_item_id: work_item.id)
created = events.find { |e| e.type == :"work_item.created" }
raise "missing work_item.created event" unless created

pass "work_item.created event recorded"

section "Step 3 — StartWorkItem (expected to fail without tmux target; catching error)"
begin
  container.start_work_item.call(work_item_id: work_item.id)
  raise "expected ArgumentError for missing tmux_target"
rescue ArgumentError => e
  pass "StartWorkItem raised expected error: #{e.message}"
end

section "Step 4 — NotifyHuman"
fake_sender = WorkCoordinator::Adapters::FakeMessageSender.new
notify = WorkCoordinator::Application::NotifyHuman.new(
  message_sender: fake_sender,
  work_item_repo: container.work_item_repo,
  event_store: container.event_store
)
waiting_item = notify.call(work_item_id: work_item.id, body: "What approach should I take?")
pass "state transitioned to: #{waiting_item.state}"
raise "expected :waiting_for_human" unless waiting_item.state == :waiting_for_human

events2 = container.event_store.all_for(work_item_id: work_item.id)
asked = events2.find { |e| e.type == :"agent.question_asked" }
raise "missing agent.question_asked event" unless asked

pass "agent.question_asked event recorded"

section "Done"
pass "All cli_wiring assertions passed"
