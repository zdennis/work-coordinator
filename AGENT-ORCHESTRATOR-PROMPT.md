# Orchestrator prompt: implement workspace agent integration in work-coordinator

You are an orchestrating agent responsible for implementing the workspace agent integration in the `work-coordinator` codebase. You will read the design and scenarios documents, then spawn and coordinate implementation agents to build the feature outside-in, driven by the acceptance scenarios.

## Read these documents first — in order

1. **Scenarios (the acceptance criteria):**
   `/Users/zdennis/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes/Projects/work-coordinator-workspace-scenarios.md`
   This is the ground truth for what to build. Section 1 is yours. Section 2 is for the workspace repo — ignore it.

2. **Wire protocol:**
   `/Users/zdennis/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes/Projects/work-coordinator-workspace-wire-protocol.md`
   The exact message shapes, socket paths, reply codes, and error handling rules.

3. **Architecture and design:**
   `/Users/zdennis/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes/Projects/work-coordinator-workspace-agent.md`

4. **Review findings (known gaps and required fixes):**
   `/Users/zdennis/Library/Mobile Documents/iCloud~md~obsidian/Documents/Notes/Projects/work-coordinator-workspace-review-findings.md`

5. **The codebase itself:**
   `/Users/zdennis/source/personal/work-coordinator/`
   Read `CLAUDE.md` in that directory for project conventions before writing any code.

## What to implement

Work through the Section 1 scenarios in the order they appear in the scenarios doc. Use outside-in ATDD: write a failing acceptance test for a scenario first, then implement the code to make it pass, then move on. Do not implement features not covered by a scenario.

### Implementation sequence (from the review findings)

1. **Work item creation on the slash-command path** — `RegisterWorkItem` must be called before forwarding any command to a workspace agent. This is a prerequisite for everything else.
2. **`rescue StandardError` in the accept-loop** — `socket_message_receiver.rb` has no rescue; one bad message kills the listener. Two lines, do this before adding any new receivers.
3. **`WorkItem` transition guards** — add `terminal?` and enforce the state graph. Phases become free-form strings (remove the fixed phase enum).
4. **Wire protocol: JSON discriminator in `SocketMessageReceiver`** — detect lines starting with `{` and route to a new `JsonMessageHandler` before the existing `ref body` split.
5. **`WorkspaceAgentRegistry`** — SQLite-backed port + adapter. Schema: `workspace_name`, `socket_path`, `pipeline` (boolean), `epoch`.
6. **`WorkspaceAgentSession` decorator** — implements `Ports::AgentSession`, wraps `TmuxAgentSession`. Checks registry; on hit, writes JSON to agent socket; on `ECONNREFUSED`, retries with exponential backoff up to 1 minute; on `ENOENT`, falls back to direct `tmux send-keys`.
7. **Status receiver** — `UNIXServer` on `/tmp/work-coordinator-status.sock`; JSON→domain-action dispatch; `message_id` dedup; `last_sequence` tracking; replies on every connection.
8. **`inject` type** — new WC→WA message for mid-pipeline human replies; synchronous reply required.
9. **`CompleteWorkItem` use case** — transitions to `:completed`, sends a "finished" notification without a reply prompt. Replace the `task_complete` → `NotifyHuman` mapping.
10. **`reply:` resolution scoped to `:waiting_for_human` items** — fix the global `last_of_type` lookup in `route_message.rb:66`; add explicit-ref syntax (`reply: WC-42 text`).

## Key conventions

- Follow the project conventions in `CLAUDE.md` exactly: ports and adapters, constructor injection, fakes not mocks, domain stays pure.
- The `WorkspaceAgentSession` decorator belongs in `lib/work_coordinator/adapters/`. It is wired in `Container` — one line change, no use case changes.
- New ports go in `lib/work_coordinator/ports/` first.
- All new adapters need a fake counterpart for tests.
- Specs go in `spec/` mirroring `lib/`. Run `bundle exec rspec` to verify after each feature.
- Commit after each scenario passes. Conventional commits: `feat(adapters):`, `feat(application):`, etc.
- Do not implement anything on the workspace side — that is a separate repo and a separate session.

## What a fake workspace agent looks like for tests

Your test suite needs a fake workspace agent to test WC's side without a real `workspace agent` process. The fake should:
- Open a `UNIXServer` on a configurable socket path
- Accept one connection, read one JSON line, write a configurable reply, close
- Be startable/stoppable in a `before`/`after` block
- Record received messages so specs can assert on them

Build this as `spec/support/fake_workspace_agent.rb` and use it across all workspace-agent-facing specs.

## Done when

All Section 1 scenarios have a passing acceptance test. `bundle exec rspec` is green. `bundle exec rubocop` is clean.
