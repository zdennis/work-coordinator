#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/domain/work_item"
require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_agent_session"
require "work_coordinator/application/event_store"
require "work_coordinator/application/route_message"

include OutputHelpers

WorkItem = WorkCoordinator::Domain::WorkItem
InMemoryWorkItemRepository = WorkCoordinator::Adapters::InMemoryWorkItemRepository
FakeAgentSession = WorkCoordinator::Adapters::FakeAgentSession
InMemoryEventStore = WorkCoordinator::Application::InMemoryEventStore
RouteMessage = WorkCoordinator::Application::RouteMessage

repo = InMemoryWorkItemRepository.new
agent_session = FakeAgentSession.new
event_store = InMemoryEventStore.new

section "Step 1 — Register work item GE-123"

work_item = WorkItem.new(
  id: "wi-1",
  title: "Update the fixture",
  kind: :jira,
  external_reference: "GE-123",
  repository: nil,
  workspace_name: nil,
  state: :active,
  phase: :implementing,
  created_at: Time.now,
  updated_at: Time.now
)
repo.save(work_item)
found = repo.find("wi-1")
raise "work item not saved" unless found&.external_reference == "GE-123"

pass "work item GE-123 registered (id=wi-1)"

section "Step 2 — Create a conversation (start agent session)"

session_id = agent_session.start_session(work_item_id: "wi-1")
raise "no session started" if session_id.nil?

pass "agent session started: #{session_id}"

section "Step 3 — Receive reply 'GE-123 yes, update the fixture'"

raw_message = "GE-123 yes, update the fixture"
info "raw_message: #{raw_message.inspect}"
pass "reply received"

section "Step 4 — Route message to agent session"

router = RouteMessage.new(work_item_repo: repo, agent_session: agent_session, event_store: event_store)
result = router.call(raw_message: raw_message)

raise "result.routed should be true, got #{result.routed}" unless result.routed

pass "message routed (routed=true)"

section "Step 5 — Assert agent received 'yes, update the fixture'"

msgs = agent_session.delivered_messages
raise "expected 1 delivered message, got #{msgs.length}" unless msgs.length == 1

expected_body = "yes, update the fixture"
actual_body = msgs.first[:message]
raise "expected body #{expected_body.inspect}, got #{actual_body.inspect}" unless actual_body == expected_body

pass "agent received correct body: #{actual_body.inspect}"

section "Step 6 — Event recorded"

events = event_store.all
raise "expected 1 event, got #{events.length}" unless events.length == 1
raise "event type should be 'human.replied', got #{events.first.type}" unless events.first.type == "human.replied"

pass "event 'human.replied' recorded"
