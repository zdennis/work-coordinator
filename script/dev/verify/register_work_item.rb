#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/domain/work_item"
require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/fake_agent_session"
require "work_coordinator/application/event_store"
require "work_coordinator/application/register_work_item"
require "work_coordinator/application/start_work_item"

include OutputHelpers

repo = WorkCoordinator::Adapters::InMemoryWorkItemRepository.new
agent_session = WorkCoordinator::Adapters::FakeAgentSession.new
event_store = WorkCoordinator::Application::InMemoryEventStore.new

section "Step 1 — Register work item"

register = WorkCoordinator::Application::RegisterWorkItem.new(
  work_item_repo: repo,
  event_store: event_store
)

work_item = register.call(title: "Update Kafka fixture", kind: :jira, external_reference: "GE-123")

raise "work_item should not be nil" unless work_item

pass "RegisterWorkItem returned a work item (id=#{work_item.id})"

section "Step 2 — Assert work item exists in repo with state: created"

found = repo.find(work_item.id)
raise "work item not found in repo" unless found
raise "expected state :created, got #{found.state}" unless found.state == :created
unless found.external_reference == "GE-123"
  raise "expected external_reference 'GE-123', got #{found.external_reference}"
end

pass "work item exists in repo with state: :created"

section "Step 3 — Assert work_item.created event recorded"

events = event_store.all
raise "expected 1 event, got #{events.length}" unless events.length == 1
raise "expected type 'work_item.created', got #{events.first.type}" unless events.first.type == "work_item.created"

pass "event 'work_item.created' recorded"

section "Step 4 — Start work item (transition to active)"

start = WorkCoordinator::Application::StartWorkItem.new(
  work_item_repo: repo,
  agent_session: agent_session,
  event_store: event_store
)

started = start.call(work_item_id: work_item.id)

raise "started work item should not be nil" unless started
raise "expected state :active, got #{started.state}" unless started.state == :active

pass "work item transitioned to :active"

section "Step 5 — Assert agent session started"

session_id = agent_session.active_session(work_item_id: work_item.id)
raise "expected an active session, got nil" unless session_id

pass "agent session started: #{session_id}"

section "Step 6 — Assert work_item.started event recorded"

events = event_store.all
started_events = events.select { |e| e.type == "work_item.started" }
raise "expected 1 work_item.started event, got #{started_events.length}" unless started_events.length == 1

pass "event 'work_item.started' recorded"
