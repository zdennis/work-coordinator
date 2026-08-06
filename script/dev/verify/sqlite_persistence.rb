#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/persistence/active_record_setup"
require "work_coordinator/adapters/sqlite_work_item_repository"
require "work_coordinator/adapters/sqlite_event_store"

include OutputHelpers

WorkCoordinator::Persistence.connect!(database: ":memory:")
WorkCoordinator::Persistence.migrate!

WorkItem = WorkCoordinator::Domain::WorkItem
Repo = WorkCoordinator::Adapters::SqliteWorkItemRepository
EventStore = WorkCoordinator::Adapters::SqliteEventStore

now = Time.now
wi1 = WorkItem.new(
  id: "wi-1",
  title: "First item",
  kind: :jira,
  external_reference: "PROJ-1",
  repository: "my-repo",
  workspace_name: "ws1",
  state: :active,
  phase: :implementing,
  created_at: now,
  updated_at: now
)
wi2 = WorkItem.new(
  id: "wi-2",
  title: "Second item",
  kind: :chore,
  external_reference: nil,
  repository: nil,
  workspace_name: "ws2",
  state: :created,
  phase: nil,
  created_at: now,
  updated_at: now
)

repo = Repo.new

section "SqliteWorkItemRepository — save"

result = repo.save(wi1)
raise "save did not return the work_item" unless result == wi1

pass "save returns the work_item"

repo.save(wi2)
pass "saved second work_item"

section "find by id"

found = repo.find("wi-1")
raise "find('wi-1') returned nil" unless found
raise "find returned wrong id: #{found.id}" unless found.id == "wi-1"
raise "find returned wrong kind: #{found.kind}" unless found.kind == :jira

pass "find('wi-1') returns correct domain object"

missing = repo.find("nonexistent")
raise "find('nonexistent') should return nil, got #{missing.inspect}" unless missing.nil?

pass "find('nonexistent') returns nil"

section "find_by_ref"

by_ref = repo.find_by_ref("PROJ-1")
raise "find_by_ref('PROJ-1') returned nil" unless by_ref
raise "find_by_ref returned wrong id: #{by_ref.id}" unless by_ref.id == "wi-1"

pass "find_by_ref('PROJ-1') returns correct item"

nil_ref = repo.find_by_ref("NO-SUCH")
raise "find_by_ref unknown ref should be nil" unless nil_ref.nil?

pass "find_by_ref unknown ref returns nil"

section "find_all"

all = repo.find_all
raise "find_all returned #{all.length} items, expected 2" unless all.length == 2

pass "find_all returns all 2 items"

section "find_all(state:)"

actives = repo.find_all(state: :active)
raise "find_all(state: :active) returned #{actives.inspect}" unless actives.length == 1 && actives.first.id == "wi-1"

pass "find_all(state: :active) returns only active items"

section "upsert / update state"

updated = wi1.with(state: :completed)
repo.save(updated)
refound = repo.find("wi-1")
raise "state after update was #{refound.state.inspect}" unless refound.state == :completed

pass "re-saving with new state updates the stored record"

section "delete"

repo.delete("wi-1")
after_delete = repo.find("wi-1")
raise "find after delete returned #{after_delete.inspect}" unless after_delete.nil?

pass "find after delete returns nil"

remaining = repo.find_all
raise "find_all after delete returned #{remaining.length} items" unless remaining.length == 1

pass "find_all after delete returns 1 remaining item"

section "SqliteEventStore — record"

store = EventStore.new
ev1 = store.record(type: :work_started, work_item_id: "wi-2", data: { note: "begin" })
raise "record returned nil" unless ev1
raise "event type mismatch: #{ev1.type}" unless ev1.type == :work_started
raise "event work_item_id mismatch" unless ev1.work_item_id == "wi-2"
raise "event data mismatch" unless ev1.data["note"] == "begin"

pass "record creates and returns Domain::Event"

store.record(type: :work_completed, work_item_id: "wi-2", data: {})
pass "recorded second event"

section "all_for"

events = store.all_for(work_item_id: "wi-2")
raise "all_for returned #{events.length} events, expected 2" unless events.length == 2

pass "all_for returns all events for work_item_id"

section "last_of_type"

last = store.last_of_type(type: :work_started, work_item_id: "wi-2")
raise "last_of_type returned nil" unless last
raise "last_of_type wrong type: #{last.type}" unless last.type == :work_started

pass "last_of_type returns the most recent matching event"

none = store.last_of_type(type: :nonexistent, work_item_id: "wi-2")
raise "last_of_type for missing type should be nil" unless none.nil?

pass "last_of_type returns nil when no match"
