# work-coordinator

A Ruby CLI that coordinates AI coding agents running in tmux panes. It tracks work items through their lifecycle, routes inbound messages (from a Unix socket or from iMessage) to the right agent pane, and notifies a human when an item needs attention. State lives in SQLite via ActiveRecord.

## Project structure

| Path | Contents |
|------|----------|
| `bin/work-coordinator` | CLI entry point — `COMMANDS` hash plus a `case` block with one OptionParser per command |
| `lib/work_coordinator/domain/` | Domain objects: `WorkItem`, `Conversation`, `Event`, `Decision`, `ResourceLease`. No infrastructure, no ActiveRecord. |
| `lib/work_coordinator/ports/` | Interfaces the domain depends on: `AgentSession`, `MessageReceiver`, `MessageSender`, `WorkItemRepository`, `WorkspaceAgentRegistry` |
| `lib/work_coordinator/adapters/` | Port implementations: tmux, Unix socket, SQLite, AppleScript, plus fakes and in-memory doubles |
| `lib/work_coordinator/adapters/workspace_agent_session.rb` | Decorator around `TmuxAgentSession` — routes delivery to a registered workspace agent's socket, falling back to tmux |
| `lib/work_coordinator/adapters/workspace_status_receiver.rb` | `UNIXServer` on the status socket; turns agent status reports into domain actions |
| `lib/work_coordinator/adapters/sqlite_workspace_agent_registry.rb` | Persists workspace agent registrations (`fake_workspace_agent_registry.rb` is its in-memory twin) |
| `lib/work_coordinator/application/` | Use cases: `RegisterWorkItem`, `StartWorkItem`, `RouteMessage`, `NotifyHuman`, `CompleteWorkItem`, `EventStore` |
| `lib/work_coordinator/application/complete_work_item.rb` | Terminal pipeline completion — moves the item to `completed` and announces it without asking for a reply |
| `lib/work_coordinator/persistence/` | ActiveRecord setup and `models/` — records are persistence detail, never passed into the domain |
| `lib/work_coordinator/container.rb` | Composition root. Opens the DB, runs migrations, picks adapters per mode, wires use cases. |
| `spec/` | RSpec suite, mirroring `lib/`; `spec/factories/` holds FactoryBot definitions |
| `spec/support/fake_workspace_agent.rb` | Test helper that simulates a workspace agent listening on a Unix socket |
| `docs/commands/` | One markdown file per CLI command |

## Key architectural patterns

**Ports and adapters.** The domain and application layers depend only on port interfaces. Every touch of the outside world — tmux, SQLite, Unix sockets, AppleScript — sits behind an adapter. Swapping tmux for another multiplexer should mean writing one new adapter and changing one line in `Container`.

**Domain-driven design.** `WorkItem` owns its state transitions; use cases orchestrate but do not reimplement domain rules. Names in code match the names used when talking about the system: work item, phase, state, route, notify.

**Dependency injection via `Container`.** Nothing constructs its own collaborators. `Container#initialize` builds adapters based on the requested modes and `Container#wire!` passes them into the use cases as keyword arguments. Constructing a container has side effects (it connects and migrates the database), so it is built once per command invocation and never inside library code.

**Modes.** `:local` uses a Unix socket; `:messages` polls the macOS Messages database. Receivers are built per mode and combined in `CompositeMessageReceiver`; the sender is picked from the modes with `:messages` winning over `:local`.

**The `WorkspaceAgentSession` decorator.** `WorkspaceAgentSession` implements `Ports::AgentSession` and wraps `TmuxAgentSession`, delegating everything it does not care about. It intercepts `deliver` to consult the `WorkspaceAgentRegistry`: on a hit it writes a JSON `command` payload to the agent's socket; on `Errno::ECONNREFUSED` it retries with exponential backoff (`BACKOFF_SECONDS`, ~1 minute total) and raises `DeliveryTimeout` if the budget runs out; on `Errno::ENOENT` the socket is gone, so it unregisters the workspace and falls back to plain tmux delivery. `inject` steers a live pipeline and reads the agent's reply — no fallback and no retry, since a steer only matters while the pipeline it interrupts is still running. This decorator is the canonical way to add routing behavior: use cases keep talking to `Ports::AgentSession` and never learn that workspace agents exist.

**Status receiver.** `WorkspaceStatusReceiver` owns its own `UNIXServer` and accept loop, the same shape as `SocketMessageReceiver`, but it is deliberately **not** a `MessageReceiver` — it carries agent telemetry, not human conversation, and nothing it receives is typed into a pane. Each connection carries one JSON message and gets one reply telling the agent whether to continue (`give_up`, `abort_pipeline`, `drop`). The CLI `run` command starts it in its own thread and stops it on shutdown.

**Debug logging.** `work-coordinator run --debug` enables structured debug output to stderr. A `Logger` is threaded through `Container` into `TmuxAgentSession`, `WorkspaceAgentSession`, `AiCommandReceiver`, `RouteMessage`, `DeliverToMainSession`, `SqliteWorkspaceAgentRegistry`, and `WorkspaceStatusReceiver`. All adapters default to `Logger.new(IO::NULL)` so tests and non-debug runs are unaffected.

**tmux window targeting.** `TmuxAgentSession` targets windows with `session:^` (first window by position) rather than `session:0`, fixing `PaneNotFoundError` for users with `base-index 1` in their tmux config. Any new tmux adapter code should follow this pattern.

## Reply routing

`RouteMessage` resolves `reply:` against **only** the items in `:waiting_for_human`. Two forms:

- **Implicit** — `reply: use Postgres` needs exactly one waiting item. Zero gives `:nothing_waiting`; more than one gives `:ambiguous_reply` and a message naming the candidates.
- **Explicit** — `reply: WC-42 use Postgres` names its target. An unknown reference gives `:unknown_reference`; a known item that is not waiting gives `:not_waiting`, with wording that distinguishes completed from abandoned.

Refusals come back as an unrouted `Result` carrying a `reason` and a `human_message`; they never raise. When the item's workspace has a registered agent, the reply is injected as a steer instead of typed into the pane, and a refused steer leaves the item waiting — the human's words never landed, so the open question stays open.

## Adding a new command

1. Add an entry to the `COMMANDS` hash in `bin/work-coordinator` — the key is the command name, the value is the one-line description shown in global help.
2. Add a `when "<name>"` branch to the `case command` block. Give it its own `OptionParser` with a banner, a prose description, an `Examples:` block, and a `-h/--help` handler.
3. Validate required arguments explicitly, `warn` a usage line, and `exit 1` on failure.
4. If the command needs a new use case, add it to `lib/work_coordinator/application/`, wire it in `Container#wire!`, and expose it through `attr_reader`.
5. Build the container in the command branch (`WorkCoordinator::Container.new`) and call the use case.
6. Add `docs/commands/<name>.md` — or run the `docs` skill.
7. Add specs covering the use case in isolation.

## Adding a new adapter

1. Confirm the port exists in `lib/work_coordinator/ports/`. If the capability is new, define the port first — it documents the contract the domain relies on.
2. Implement the adapter in `lib/work_coordinator/adapters/`, taking every collaborator through the constructor.
3. Add a fake or in-memory counterpart if tests need one (`fake_*.rb` or `in_memory_*.rb` alongside it).
4. Wire it in `Container` — for a receiver, add a `when` branch in `build_receivers`; for a sender, extend `build_sender`.
5. Spec the adapter directly against its real dependency where feasible, and use the fake everywhere else.

## Conventions

- **Constructor injection everywhere.** Collaborators arrive as keyword arguments. No globals, no singletons, no `Adapter.new` inside a use case.
- **Fakes, not mocks, for internal classes.** Use `FakeAgentSession`, `FakeMessageSender`, `InMemoryWorkItemRepository`. Do not `allow`/`expect` on classes we own — if a fake is awkward to write, the seam is in the wrong place.
- **Use `FakeWorkspaceAgent` for socket-facing specs.** Any spec exercising code that talks to a workspace agent socket uses `spec/support/fake_workspace_agent.rb`: it opens a `UNIXServer`, accepts one connection, records the JSON it receives, and writes a configurable `reply`. Start it in `before`, `stop` it in `after`, and use `wait_for_message` to synchronize.
- **Mocks are acceptable only at true system boundaries** where no fake is practical, and even then prefer a thin adapter that can be faked.
- **Domain stays pure.** No ActiveRecord, no shelling out, no `ENV` reads below the adapter layer.
- **Conventional commits.** `feat(scope):`, `fix(scope):`, `refactor(scope):`, `chore(scope):`, `docs(scope):`. Scope is usually a layer (`cli`, `adapters`, `domain`, `container`).
- **All tests must pass before committing.** No exceptions, no `--no-verify`.

## Pre-commit requirements

Before every commit, run all review agents **in parallel** in a single message:

- `staff-engineer` — does the change earn its complexity?
- `testing-craftsperson` — coverage, fakes, suite and lint status
- `ddd-hexagonal-expert` — domain modeling and boundary integrity
- `ai-agent-operator` — output parseability and exit codes
- `new-user` — help text, error messages, docs

Address anything they return as **Concerns** before committing. If a concern is a deliberate tradeoff, say so in the commit body.

## Testing

```bash
bundle exec rspec              # full suite
bundle exec rspec spec/path    # focused run
bundle exec rubocop            # lint
bundle exec rubocop -A         # autocorrect
```

Tests must not need a live tmux session, a real socket, or the Messages database. If a test reaches for one of those, the code under test is missing a port.

## Analysis output

Structure analysis and review output using the Pyramid Principle:

1. **Verdict first** — one line: pass, concerns, or the answer to the question asked.
2. **Recommendations** — the actions that follow from the verdict, ordered by value.
3. **Supporting detail** — evidence, `file:line` references, and reasoning, for readers who want it.

Never bury the conclusion under the analysis that produced it.
