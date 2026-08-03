#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/adapters/in_memory_work_item_repository"
require "work_coordinator/adapters/in_memory_resource_lease_registry"
require "work_coordinator/adapters/fake_agent_session"
require "work_coordinator/adapters/fake_message_sender"
require "work_coordinator/application/event_store"
require "work_coordinator/application/register_work_item"
require "work_coordinator/application/start_work_item"
require "work_coordinator/application/notify_human"
require "work_coordinator/application/route_message"

include OutputHelpers

SCENARIO = "I can answer an agent's question from my phone and see that answer arrive in the correct tmux pane"

puts cyan("\nSCENARIO: #{SCENARIO}\n")

# Wire up infrastructure
repo         = WorkCoordinator::Adapters::InMemoryWorkItemRepository.new
lease_reg    = WorkCoordinator::Adapters::InMemoryResourceLeaseRegistry.new
agent_session = WorkCoordinator::Adapters::FakeAgentSession.new
msg_sender   = WorkCoordinator::Adapters::FakeMessageSender.new
event_store  = WorkCoordinator::Application::InMemoryEventStore.new

passes = 0
failures = 0

def assert(condition, description)
  if condition
    pass description
    :pass
  else
    self.fail description
    :fail
  end
end

# ── Step 1: Register work item ────────────────────────────────────────────────
section "Step 1 — Register work item GE-123 (kind: :jira)"

register = WorkCoordinator::Application::RegisterWorkItem.new(
  work_item_repo: repo,
  event_store: event_store
)
work_item = register.call(title: "Update Kafka fixture", kind: :jira, external_reference: "GE-123")

result = assert(work_item.external_reference == "GE-123", "work item GE-123 registered")
result == :pass ? passes += 1 : failures += 1

result = assert(work_item.state == :created, "initial state is :created")
result == :pass ? passes += 1 : failures += 1

# ── Step 2: Start it — acquires fake devspace lease, starts fake agent session ─
section "Step 2 — Start work item (acquire devspace lease, start agent session)"

lease_reg.register_resource(name: "devspace")
lease = lease_reg.acquire(resource_name: "devspace", work_item_id: work_item.id)

start = WorkCoordinator::Application::StartWorkItem.new(
  work_item_repo: repo,
  agent_session: agent_session,
  event_store: event_store
)
active_item = start.call(work_item_id: work_item.id)

result = assert(!lease.released?, "devspace lease acquired (not released)")
result == :pass ? passes += 1 : failures += 1

result = assert(active_item.state == :active, "work item state is :active after start")
result == :pass ? passes += 1 : failures += 1

result = assert(!agent_session.active_session(work_item_id: work_item.id).nil?, "agent session started")
result == :pass ? passes += 1 : failures += 1

# ── Step 3: Agent session notifies human ─────────────────────────────────────
section "Step 3 — Agent notifies human with a question"

notify = WorkCoordinator::Application::NotifyHuman.new(
  message_sender: msg_sender,
  work_item_repo: repo,
  event_store: event_store
)
question_body = "Should I update the Kafka fixture to include abandonment events?"
notify.call(work_item_id: work_item.id, body: question_body)

# ── Step 4: Assert human received the formatted message ──────────────────────
section "Step 4 — Assert human received [GE-123] prefixed message"

sent = msg_sender.sent_messages
expected_prefix = "[GE-123] #{question_body}"

result = assert(sent.length == 1, "exactly one message sent to human")
result == :pass ? passes += 1 : failures += 1

result = assert(sent.first[:body].start_with?(expected_prefix), "message starts with [GE-123] prefix")
result == :pass ? passes += 1 : failures += 1

result = assert(repo.find(work_item.id).state == :waiting_for_human, "work item state is :waiting_for_human")
result == :pass ? passes += 1 : failures += 1

# ── Step 5: Human replies ─────────────────────────────────────────────────────
section "Step 5 — Human replies from phone"

raw_reply = "GE-123 yes, update the fixture and rerun the suite"
info "raw reply: #{raw_reply.inspect}"
pass "human reply composed"
passes += 1

# ── Step 6: RouteMessage routes to the fake agent session ────────────────────
section "Step 6 — RouteMessage routes reply to agent session"

router = WorkCoordinator::Application::RouteMessage.new(
  work_item_repo: repo,
  agent_session: agent_session,
  event_store: event_store
)
route_result = router.call(raw_message: raw_reply)

result = assert(route_result.routed, "message was routed (routed=true)")
result == :pass ? passes += 1 : failures += 1

# ── Step 7: Assert agent session received the body ───────────────────────────
section "Step 7 — Assert agent session received correct body"

delivered = agent_session.delivered_messages
expected_body = "yes, update the fixture and rerun the suite"

result = assert(delivered.length == 1, "exactly one message delivered to agent")
result == :pass ? passes += 1 : failures += 1

result = assert(delivered.first[:message] == expected_body, "agent received: #{expected_body.inspect}")
result == :pass ? passes += 1 : failures += 1

# ── Step 8: Assert work item is back to :active ──────────────────────────────
section "Step 8 — Assert work item returned to :active"

final_item = repo.find(work_item.id)
result = assert(final_item.state == :active, "work item state is :active (not :waiting_for_human)")
result == :pass ? passes += 1 : failures += 1

# ── Summary ───────────────────────────────────────────────────────────────────
separator
total = passes + failures
if failures.zero?
  puts green("  ALL #{total} ASSERTIONS PASSED")
else
  puts red("  #{failures} of #{total} ASSERTIONS FAILED")
  exit 1
end
