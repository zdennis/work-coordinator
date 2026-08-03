#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/domain/conversation"
require "work_coordinator/domain/event"
require "work_coordinator/domain/decision"

include OutputHelpers

Conversation = WorkCoordinator::Domain::Conversation
Event        = WorkCoordinator::Domain::Event
Decision     = WorkCoordinator::Domain::Decision

# ── Conversation ──────────────────────────────────────────────────────────────

section "Conversation construction"

now = Time.now
conv = Conversation.new(
  id: "c-1",
  work_item_id: "wi-1",
  message_thread_id: "mt-42",
  agent_session: "session-abc",
  last_inbound_at: now,
  last_outbound_at: now
)
pass "Conversation created successfully"

section "Conversation field access"

pass "id: #{conv.id}"                           if conv.id == "c-1"
pass "work_item_id: #{conv.work_item_id}"       if conv.work_item_id == "wi-1"
pass "message_thread_id: #{conv.message_thread_id}" if conv.message_thread_id == "mt-42"
pass "agent_session: #{conv.agent_session}"     if conv.agent_session == "session-abc"
pass "last_inbound_at present"                  if conv.last_inbound_at
pass "last_outbound_at present"                 if conv.last_outbound_at

section "Conversation allows nil optional fields"

conv2 = Conversation.new(
  id: "c-2",
  work_item_id: "wi-2",
  message_thread_id: nil,
  agent_session: nil,
  last_inbound_at: nil,
  last_outbound_at: nil
)
pass "nil optional fields accepted" if conv2.agent_session.nil?

# ── Event ─────────────────────────────────────────────────────────────────────

section "Event construction"

evt = Event.new(
  id: "e-1",
  work_item_id: "wi-1",
  type: "state_changed",
  source: "coordinator",
  data: { from: :created, to: :active },
  occurred_at: now
)
pass "Event created successfully"

section "Event field access"

pass "id: #{evt.id}"                         if evt.id == "e-1"
pass "work_item_id: #{evt.work_item_id}"     if evt.work_item_id == "wi-1"
pass "type: #{evt.type}"                     if evt.type == "state_changed"
pass "source: #{evt.source}"                 if evt.source == "coordinator"
pass "data is hash"                          if evt.data.is_a?(Hash)
pass "occurred_at present"                   if evt.occurred_at

# ── Decision ──────────────────────────────────────────────────────────────────

section "Decision construction"

dec = Decision.new(
  id: "d-1",
  work_item_id: "wi-1",
  title: "Use Sidekiq for background jobs",
  status: :proposed,
  context: "We need async processing",
  decision_text: "Adopt Sidekiq",
  consequences: "Must run Redis",
  source: "architect",
  created_at: now
)
pass "Decision created successfully"

section "Decision field access"

pass "id: #{dec.id}"                           if dec.id == "d-1"
pass "work_item_id: #{dec.work_item_id}"       if dec.work_item_id == "wi-1"
pass "title: #{dec.title}"                     if dec.title == "Use Sidekiq for background jobs"
pass "status: #{dec.status}"                   if dec.status == :proposed
pass "context present"                         if dec.context
pass "decision_text present"                   if dec.decision_text
pass "consequences present"                    if dec.consequences
pass "source: #{dec.source}"                   if dec.source == "architect"
pass "created_at present"                      if dec.created_at

section "Decision status predicates"

statuses = %i[proposed accepted superseded rejected]
statuses.each do |s|
  d = dec.with(status: s)
  pred = :"#{s}?"
  raise "#{pred} should be true when status=#{s}" unless d.public_send(pred)

  pass "#{pred} true when status=#{s}"

  other = statuses.reject { |x| x == s }.first
  d2 = dec.with(status: other)
  raise "#{pred} should be false when status=#{other}" if d2.public_send(pred)

  pass "#{pred} false when status=#{other}"
end
