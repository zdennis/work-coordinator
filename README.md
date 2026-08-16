# work-coordinator

Route messages to AI agents — running in tmux panes, or behind a workspace agent that owns those panes itself.

## Overview

When you run AI coding agents in tmux panes, each one eventually stops and waits on you. Answering means finding the right pane, remembering which task it belongs to, and typing into it. work-coordinator removes that step: work items are registered with an external reference (a Jira ticket, an issue number), and any message prefixed with that reference is routed to the agent working it.

Messages arrive through two channels. **Local socket mode** listens on a Unix domain socket, so `work-coordinator send 'MS-123 go ahead'` from any terminal lands in the right place. **Messages.app mode** polls `~/Library/Messages/chat.db` on macOS, so an agent can text you a question and you can answer from your iPhone. Both run at once by default.

Delivery has two paths. By default work-coordinator types into a tmux pane. But a workspace can instead run a **workspace agent** — a long-lived per-workspace process that registers itself with work-coordinator, receives commands as JSON over its own Unix socket, runs its own multi-pane pipeline, and reports progress back. When a workspace has a live registration, commands go to the agent; when it does not, they fall back to `tmux send-keys`. See [Workspace agent integration](#workspace-agent-integration).

State lives in SQLite. A work item tracks a UUID, title, kind, external reference, repository, workspace, and tmux target, and moves through `created` → `active` → `waiting_for_human` → `completed`. Workspace agent registrations live in SQLite too, so they survive a work-coordinator restart.

## Prerequisites

- Ruby >= 3.2 and Bundler (`gem install bundler`)
- tmux
- macOS with Messages.app configured, for messages mode only

## Installation

```bash
git clone <repo-url> work-coordinator
cd work-coordinator
bin/setup
```

`bin/setup` installs Homebrew dependencies, the pinned Ruby version via rbenv, and gems. If you manage Ruby yourself, `bundle install` is enough.

## Quick start

Local socket mode, four steps.

**1. Create a tmux session for the agent.**

```bash
tmux new-session -d -s my-project -n claude
```

The `-n claude` flag names the window, making the pane addressable as `my-project:claude.0` (`session:window.pane`).

**2. Register a work item.**

```bash
bundle exec ruby bin/work-coordinator register \
  --title "Fix Kafka abandonment fixture" \
  --kind  jira \
  --ref   MS-123 \
  --repo  acme-billing \
  --tmux  my-project:claude.0
```

```
id:    71380947-2ce7-4799-adbf-be9516583b45
state: created
```

Migrations run automatically on first invocation.

**3. Start the coordinator, in its own terminal.**

```bash
bundle exec ruby bin/work-coordinator run --mode local
```

```
work-coordinator running on /tmp/work-coordinator.sock (local socket)
Press Ctrl-C to stop.
```

**4. Route a message from another terminal.**

```bash
bundle exec ruby bin/work-coordinator send "MS-123 yes, update the fixture and rerun the suite"
```

The message format is `<REF> <body>`. The REF must match the registered reference exactly (case-sensitive) and be separated from the body by a single space. The coordinator strips the REF and delivers only the body to the pane.

Check where things stand with `work-coordinator status`.

## Replying to an agent

When an agent asks you something, work-coordinator moves the item to `waiting_for_human` and notifies you. You answer with a `reply:` message:

```bash
work-coordinator send "reply: use Postgres, not SQLite"
```

The implicit form works when exactly one item is waiting. If several are, the reply is refused and work-coordinator tells you which items are open, so you can name one explicitly:

```bash
work-coordinator send "reply: MS-123 use Postgres, not SQLite"
```

Explicit refs are resolved against the work item's external reference. A ref that names no known item, or names one that is not waiting (already `completed`, `abandoned`, or still working), is refused with a message saying so rather than delivered to the wrong agent. Refusals are visible in the result's `reason` (`unknown_reference`, `not_waiting`, `nothing_waiting`, `ambiguous_reply`, `inject_failed`).

A delivered reply carries the original question along with it, so the agent sees the context it asked about and not just your answer.

## Workspace agent integration

A **workspace agent** is an autonomous daemon owning one workspace. Rather than having work-coordinator type into its panes, it accepts structured commands, decides how to run them across its own pipeline of panes, and reports back. work-coordinator stays the router and the human's front door; the agent owns execution.

```
  human (iMessage / work-coordinator send)
      │
      ▼
┌─────────────────────────┐   registry lookup: is this workspace registered?
│    work-coordinator     │──────────────┬──────────────────────┐
│  RouteMessage           │        yes   │                   no │
│  WorkspaceAgentSession  │              ▼                      ▼
└─────────────────────────┘   ┌────────────────────┐   ┌────────────────┐
      ▲                       │  workspace agent   │   │  tmux pane     │
      │                       │  /tmp/wa-<name>... │   │  send-keys     │
      │                       └────────┬───────────┘   └────────────────┘
      │                                │ owns its own pipeline
      │                                ▼
      │                       ┌────────────────────┐
      │                       │ tmux panes 0..n    │
      │                       └────────┬───────────┘
      │  status_update / phase_change / task_complete / error
      └────────────────────────────────┘
         /tmp/work-coordinator-status.sock
```

### Registration lifecycle

An agent registers itself on startup by sending a `register` message to work-coordinator's main socket, naming its workspace, its own socket path, whether it runs a pipeline, and its epoch. It sends `deregister` on shutdown. Registrations persist in the `workspace_agent_registrations` table, so an agent that registered before work-coordinator restarted is still routable afterwards.

A workspace can only be claimed once. Re-registering under the same epoch is treated as the same process refreshing its listener and updates the row; a different epoch is a second process and is refused with `already_registered`.

### Command routing

`WorkspaceAgentSession` (`lib/work_coordinator/adapters/workspace_agent_session.rb`) decorates the tmux session and makes the routing decision on every delivery:

1. Look the workspace up in the registry. No entry — or no work item ref to address the agent with — means straight to tmux.
2. On a hit, connect to the agent's socket and write one JSON `command` line. Commands are fire-and-forget: accepting the write is the acknowledgement.
3. `ECONNREFUSED` means the socket file exists but nothing is listening — usually an agent mid-restart. Retry with exponential backoff (1, 2, 4, 8, 16, 32 seconds, about a minute total). Exhausting the budget raises `DeliveryTimeout` rather than falling back, because a registered agent that will not answer is something a human needs to hear about.
4. `ENOENT` means the socket is gone for good. The registration is deleted on the spot and the message goes to tmux, so the next delivery skips the dead agent entirely.

### Status reporting

Agents report back over a second socket, `/tmp/work-coordinator-status.sock` (override with `WC_STATUS_SOCKET`), served by `WorkspaceStatusReceiver`. One JSON message per connection, one reply per connection — the reply tells the agent whether to keep going.

| Incoming type | Effect |
|---------------|--------|
| `status_update` | Records an `agent.status_update` event |
| `phase_change` | Updates the work item's phase (free-form string) and records `agent.phase_changed` |
| `pipeline_advanced` | Records `agent.pipeline_advanced` with the from/to panes |
| `task_complete` | Runs `CompleteWorkItem`: transitions to `completed` and texts the human a summary with no reply prompt |
| `error` | Notifies the human |

Every message is gated before it is applied. A repeated `message_id` is acknowledged without re-applying. A `sequence` at or below the last one seen for that workspace and ref is answered `out_of_sequence` with `action: "drop"`. An unknown `work_item_ref` gets `unknown_work_item` with `action: "give_up"`, and a ref whose item already reached a terminal state gets `terminal_state` with `action: "abort_pipeline"` — a signal to the agent to stop the pipeline it is running. Successful replies carry the receiver's `epoch`, which changes whenever work-coordinator restarts.

### Mid-pipeline steering

A human reply to an item in a registered workspace is not typed into a pane — it is sent to the agent as an `inject` message and work-coordinator waits for the answer. Unlike a command, a steer is not retried and never falls back to tmux: it is only meaningful while the pipeline it interrupts is still running. A refused steer (`no_registration`, `agent_gone`, `agent_unavailable`, `no_reply`, `malformed_reply`) leaves the item waiting and notifies the human, because their words never reached the agent.

### Wire protocol

Both directions are JSON Lines over Unix domain sockets — one object per line, one message per connection.

| Direction | Type | Purpose |
|-----------|------|---------|
| agent → WC | `register` | Claim a workspace, giving socket path, pipeline flag, and epoch |
| agent → WC | `deregister` | Release the workspace on shutdown |
| agent → WC | `status_update`, `phase_change`, `pipeline_advanced` | Progress telemetry |
| agent → WC | `task_complete` | Work is finished; carries a `summary` |
| agent → WC | `error` | Something failed; carries a `message` |
| WC → agent | `command` | A dispatched instruction; fire-and-forget |
| WC → agent | `inject` | A human steer mid-pipeline; synchronous reply required |

Outbound messages carry `type`, `workspace`, `work_item_ref`, a generated `dispatch_id`, and `body`; `inject` adds `interrupt`. Inbound status messages carry `type`, `workspace`, `work_item_ref`, and optionally `message_id` and `sequence` for dedup and ordering.

## Commands

| Command | Description |
|---------|-------------|
| [`init`](docs/commands/init.md) | Create the default config file |
| [`alias`](docs/commands/alias.md) | List, add, or remove workspace project aliases |
| [`config`](docs/commands/config.md) | Read or write a configuration property |
| [`register`](docs/commands/register.md) | Create a work item and print its UUID |
| [`start <uuid>`](docs/commands/start.md) | Transition a work item to `active` |
| [`status`](docs/commands/status.md) | List all work items with state, phase, and title |
| [`run`](docs/commands/run.md) | Start the daemon and listen for inbound messages |
| [`send "REF body"`](docs/commands/send.md) | Send a message to the running daemon over its socket |
| [`notify <uuid> "body"`](docs/commands/notify.md) | Send a human notification for a work item |

Run `work-coordinator <command> --help` for command-specific options.

## Modes

`run` enables all modes by default. Restrict with `--mode` (repeatable, comma-separated).

| Mode | Behavior |
|------|----------|
| `all` | Every known mode; currently equivalent to `local,messages`. The default. |
| `local` | Opens a Unix socket at `WC_SOCKET` and listens for `work-coordinator send`. |
| `messages` | Polls `~/Library/Messages/chat.db` for iMessages prefixed with `ai: `. Requires `WC_RECIPIENT`. |

```bash
work-coordinator run --mode local
work-coordinator run -m local,messages
WC_RECIPIENT=+1XXXXXXXXXX work-coordinator run --mode messages
```

Messages mode requires two things beyond the recipient. Your terminal app needs Full Disk Access (System Settings → Privacy & Security → Full Disk Access) — grant it, then quit and relaunch the terminal, and run `tmux kill-server` if a tmux server was already running, since permissions are inherited at launch. And every reply from your phone must begin with `ai: `, which filters out unrelated messages in the thread:

```
ai: MS-123 yes, update the fixture and rerun the suite
```

See [docs/quickstart.md](docs/quickstart.md) for the full messages-mode walkthrough and troubleshooting table.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path used in local mode |
| `WC_STATUS_SOCKET` | `/tmp/work-coordinator-status.sock` | Unix socket workspace agents report status to |
| `WC_RECIPIENT` | _(required for messages mode)_ | Phone number or email for outbound notifications |

## Development

```bash
bundle exec rspec        # test suite
bundle exec rubocop      # lint
```

`script/dev/verify/` holds standalone scenario exercisers that run against fake adapters, so they need no tmux session, socket, or Messages.app:

```bash
ruby script/dev/verify/loopback_e2e.rb
```

See [script/dev/verify/README.md](script/dev/verify/README.md) for conventions.

## Contributing

1. Fork the repository and branch from `main`.
2. Make your change, with tests.
3. Ensure `bundle exec rspec` and `bundle exec rubocop` both pass.
4. Write commit messages in [Conventional Commits](https://www.conventionalcommits.org/) form (`feat:`, `fix:`, `docs:`, `refactor:`).
5. Open a pull request describing what changed and why.

## License

MIT. A `LICENSE` file has not been added to the repository yet.
