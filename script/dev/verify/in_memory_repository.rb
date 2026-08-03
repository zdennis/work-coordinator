#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/domain/work_item"
require "work_coordinator/adapters/in_memory_work_item_repository"

include OutputHelpers

WorkItem = WorkCoordinator::Domain::WorkItem
Repo = WorkCoordinator::Adapters::InMemoryWorkItemRepository

now = Time.now
wi1 = WorkItem.new(
  id: "1",
  title: "First item",
  kind: :jira,
  external_reference: "PROJ-1",
  repository: "repo",
  workspace_name: "ws",
  state: :active,
  phase: :implementing,
  created_at: now,
  updated_at: now
)
wi2 = WorkItem.new(
  id: "2",
  title: "Second item",
  kind: :chore,
  external_reference: nil,
  repository: nil,
  workspace_name: "ws",
  state: :created,
  phase: :investigating,
  created_at: now,
  updated_at: now
)

section "InMemoryWorkItemRepository — save"

repo = Repo.new
result = repo.save(wi1)
raise "save did not return the work_item" unless result == wi1

pass "save returns the work_item"

repo.save(wi2)
pass "saved second work_item"

section "find by id"

found = repo.find("1")
raise "find('1') returned wrong value: #{found.inspect}" unless found == wi1

pass "find('1') returns wi1"

missing = repo.find("nonexistent")
raise "find('nonexistent') should return nil, got #{missing.inspect}" unless missing.nil?

pass "find('nonexistent') returns nil"

section "find_all"

all = repo.find_all
raise "find_all returned #{all.length} items, expected 2" unless all.length == 2

pass "find_all returns all 2 items"

section "find_all(status: :active)"

actives = repo.find_all(status: :active)
raise "find_all(status: :active) returned #{actives.inspect}" unless actives.length == 1 && actives.first.id == "1"

pass "find_all(status: :active) returns only active items"

section "update state"

updated = wi1.with(state: :completed)
repo.save(updated)
refound = repo.find("1")
raise "state after update was #{refound.state.inspect}, expected :completed" unless refound.state == :completed

pass "re-saving with new state updates the stored item"

section "delete"

repo.delete("1")
after_delete = repo.find("1")
raise "find after delete returned #{after_delete.inspect}" unless after_delete.nil?

pass "find after delete returns nil"

remaining = repo.find_all
raise "find_all after delete returned #{remaining.inspect}" unless remaining.length == 1 && remaining.first.id == "2"

pass "find_all after delete returns only remaining items"
