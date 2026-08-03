#!/usr/bin/env ruby
# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

require_relative "support/output_helpers"
require "work_coordinator/adapters/fake_agent_session"

include OutputHelpers

FakeAgentSession = WorkCoordinator::Adapters::FakeAgentSession

section "FakeAgentSession — start_session"

adapter = FakeAgentSession.new
session_id = adapter.start_session(work_item_id: "wi-1")
raise "start_session did not return a session_id" if session_id.nil?

pass "start_session returns a session_id"

section "active_session"

active = adapter.active_session(work_item_id: "wi-1")
raise "active_session returned #{active.inspect}, expected #{session_id}" unless active == session_id

pass "active_session returns session_id for work_item"

missing = adapter.active_session(work_item_id: "wi-999")
raise "active_session for unknown work_item should be nil, got #{missing.inspect}" unless missing.nil?

pass "active_session returns nil for unknown work_item"

section "deliver"

adapter.deliver(session_id: session_id, message: "Hello agent")
adapter.deliver(session_id: session_id, message: "Second message")

msgs = adapter.delivered_messages
raise "expected 2 delivered messages, got #{msgs.length}" unless msgs.length == 2
raise "first message wrong: #{msgs[0].inspect}" unless msgs[0] == { session_id: session_id, message: "Hello agent" }
raise "second message wrong: #{msgs[1].inspect}" unless msgs[1] == { session_id: session_id, message: "Second message" }

pass "delivered_messages returns all delivered messages in order"

section "end_session"

adapter.end_session(session_id: session_id)
active_after = adapter.active_session(work_item_id: "wi-1")
raise "active_session after end_session should be nil, got #{active_after.inspect}" unless active_after.nil?

pass "end_session removes the active session"
