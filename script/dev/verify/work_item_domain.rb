#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/domain/work_item"

include OutputHelpers

WorkItem = WorkCoordinator::Domain::WorkItem

section "WorkItem construction"

wi = WorkItem.new(
  id: "1",
  title: "Fix the thing",
  kind: :jira,
  external_reference: "PROJ-123",
  repository: "my-repo",
  workspace_name: "workspace-1",
  state: :created,
  phase: :investigating,
  created_at: Time.now,
  updated_at: Time.now
)

pass "WorkItem created successfully"

section "Field access"

pass "id: #{wi.id}" if wi.id == "1"
pass "title: #{wi.title}" if wi.title == "Fix the thing"
pass "kind: #{wi.kind}" if wi.kind == :jira
pass "external_reference: #{wi.external_reference}" if wi.external_reference == "PROJ-123"
pass "repository: #{wi.repository}" if wi.repository == "my-repo"
pass "workspace_name: #{wi.workspace_name}" if wi.workspace_name == "workspace-1"
pass "state: #{wi.state}" if wi.state == :created
pass "phase: #{wi.phase}" if wi.phase == :investigating
pass "created_at present" if wi.created_at
pass "updated_at present" if wi.updated_at

section "State predicates"

states = %i[created ready active waiting_for_human waiting_for_resource blocked completed abandoned]
predicates = {
  created: :created?,
  ready: :ready?,
  active: :active?,
  waiting_for_human: :waiting_for_human?,
  waiting_for_resource: :waiting_for_resource?,
  blocked: :blocked?,
  completed: :completed?,
  abandoned: :abandoned?
}

states.each do |s|
  item = wi.with(state: s)
  pred = predicates[s]
  raise "#{pred} should be true when state=#{s}" unless item.public_send(pred)

  pass "#{pred} true when state=#{s}"

  other = states.reject { |x| x == s }.first
  other_item = wi.with(state: other)
  raise "#{pred} should be false when state=#{other}" if other_item.public_send(pred)

  pass "#{pred} false when state=#{other}"
end

section "state? helper"

item = wi.with(state: :active)
raise "state?(:active) should be true" unless item.state?(:active)

pass "state?(:active) true when state=:active"

raise "state?(:blocked) should be false" if item.state?(:blocked)

pass "state?(:blocked) false when state=:active"

section "Compatibility aliases (open?, done?, in_progress?)"

open_item = wi.with(state: :created)
pass "open? true when state=:created" if open_item.open?

done_item = wi.with(state: :completed)
pass "done? true when state=:completed" if done_item.done?

active_item = wi.with(state: :active)
pass "in_progress? true when state=:active" if active_item.in_progress?

section "Valid kinds"

%i[jira chore investigation adhoc].each do |k|
  item = wi.with(kind: k)
  raise "kind=#{k} not accepted" unless item.kind == k

  pass "kind=#{k} accepted"
end

section "Valid phases"

%i[investigating implementing verifying reviewing].each do |p|
  item = wi.with(phase: p)
  raise "phase=#{p} not accepted" unless item.phase == p

  pass "phase=#{p} accepted"
end
