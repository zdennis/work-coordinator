#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "support/output_helpers"
require_relative "../../../lib/work_coordinator/domain/resource_lease"
require_relative "../../../lib/work_coordinator/adapters/in_memory_resource_lease_registry"

include OutputHelpers

def check(condition, pass_msg, fail_msg)
  condition ? pass(pass_msg) : self.fail(fail_msg)
end

section "ResourceLease domain model"

lease = WorkCoordinator::Domain::ResourceLease.new(
  id: "lease-1",
  resource_name: "devspace",
  work_item_id: "item-A",
  acquired_at: Time.now,
  released_at: nil
)
check(!lease.released?, "new lease is not released", "new lease should not be released")

released = lease.with(released_at: Time.now)
check(released.released?, "released lease reports released?=true", "released lease should report released?=true")

section "InMemoryResourceLeaseRegistry — capacity-1 Devspace"

registry = WorkCoordinator::Adapters::InMemoryResourceLeaseRegistry.new
registry.register_resource(name: "devspace", capacity: 1)

lease_a = registry.acquire(resource_name: "devspace", work_item_id: "item-A")
check(lease_a, "item-A acquired devspace lease", "item-A should acquire devspace lease")

lease_b = registry.acquire(resource_name: "devspace", work_item_id: "item-B")
check(lease_b.nil?, "item-B blocked (capacity held by item-A)", "item-B should be blocked")

holder = registry.current_holder("devspace")
check(holder == "item-A", "current_holder returns item-A", "current_holder should be item-A, got #{holder.inspect}")

registry.release(resource_name: "devspace", work_item_id: "item-A")

lease_b2 = registry.acquire(resource_name: "devspace", work_item_id: "item-B")
check(lease_b2, "item-B acquired devspace lease after release", "item-B should acquire after release")

holder2 = registry.current_holder("devspace")
check(holder2 == "item-B", "current_holder is now item-B", "current_holder should be item-B, got #{holder2.inspect}")

waiting = registry.waiting("devspace")
check(waiting.empty?, "waiting list is empty", "waiting should be empty, got #{waiting.inspect}")
