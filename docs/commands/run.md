# run

Starts the coordinator daemon, opens inbound message channels, and routes messages to registered tmux panes or workspace agents.

```
work-coordinator run [options]
```

By default `run` enables all modes — local socket and Messages.app polling — simultaneously. Use `--mode` to restrict to a specific subset.

## Options

| Flag | Description |
|------|-------------|
| `-m`, `--mode MODE` | Receive mode. Repeatable and comma-separated. Valid values: `all`, `local`, `messages`. Defaults to `all`. |
| `--debug` | Enable debug logging to stderr. Prints routing decisions, registry hits and misses, tmux targets, and agent registration events as they happen. |
| `--role ROLE` | Role this coordinator answers to, overriding the `role:` key in `config.yml` for this run. |

The role names this coordinator so messages can be addressed to it when more
than one coordinator is running. Alongside `role:`, the config file accepts
`role_aliases:` — a list of other names the same coordinator answers to:

```yaml
role: home
role_aliases:
  - house
  - casa
```

The `--mode` flag can be given multiple times or with a comma-separated list:

```bash
work-coordinator run -m local,messages
work-coordinator run -m local -m messages
```

Both forms are equivalent to the default `all`.

## Modes

| Mode | What it does |
|------|--------------|
| `all` | Enables every known mode. Currently equivalent to `local,messages`. This is the default when no `--mode` is given. |
| `local` | Opens a Unix domain socket at `WC_SOCKET` (default `~/.local/run/work-coordinator/work-coordinator.sock`) and listens for messages sent via `work-coordinator send`. |
| `messages` | Polls `~/Library/Messages/chat.db` every few seconds for iMessages prefixed with `ai: `. Requires `WC_RECIPIENT` to be set. |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_RUN_DIR` | `~/.local/run/work-coordinator` | Directory for runtime files (sockets); overrides all socket path defaults |
| `WC_SOCKET` | `$WC_RUN_DIR/work-coordinator.sock` | Unix socket path used in `local` mode |
| `WC_STATUS_SOCKET` | `$WC_RUN_DIR/work-coordinator-status.sock` | Unix socket path for inbound workspace agent status reports |
| `WC_RECIPIENT` | _(required for messages mode)_ | Phone number or email address for outbound notifications |
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |

## Startup banner

Each enabled mode prints a line when the daemon starts.

Local mode:

```
work-coordinator running on ~/.local/run/work-coordinator/work-coordinator.sock (local socket)
Press Ctrl-C to stop.
```

Messages mode:

```
work-coordinator running in messages mode (polling ~/Library/Messages/chat.db)
Listening for messages starting with: ai:
Press Ctrl-C to stop.
```

Both modes together (default):

```
work-coordinator running on ~/.local/run/work-coordinator/work-coordinator.sock (local socket)
work-coordinator running in messages mode (polling ~/Library/Messages/chat.db)
Listening for messages starting with: ai:
Press Ctrl-C to stop.
```

The status socket line is printed after the mode lines regardless of which modes are enabled:

```
Accepting workspace agent status reports on ~/.local/run/work-coordinator/work-coordinator-status.sock
```

## Workspace agent status socket

Alongside the mode receivers, `run` always starts a `WorkspaceStatusReceiver` on its own thread,
listening at `WC_STATUS_SOCKET` (default `~/.local/run/work-coordinator/work-coordinator-status.sock`). This is a second,
separate socket from `WC_SOCKET` — it exists so that agents running inside a workspace can report
their own progress back to the coordinator without going through the human message path.

Each connection carries exactly one JSON line and gets exactly one JSON line back before the
connection closes. The receiver handles five message types:

| Type | Effect |
|------|--------|
| `status_update` | Appends an `agent.status_update` event to the work item |
| `phase_change` | Sets the work item's `phase` and appends `agent.phase_changed` |
| `pipeline_advanced` | Appends `agent.pipeline_advanced` with `from_pane` and `to_pane` |
| `task_complete` | Runs `CompleteWorkItem` with the reported summary |
| `error` | Runs `NotifyHuman` with the reported message |

Every message names its work item by `work_item_ref`. An unknown ref, or a ref belonging to an item
already in a terminal state, is refused with a reply telling the agent what to do next rather than
being silently dropped. Messages carrying a `message_id` are deduplicated, and messages carrying a
`sequence` that has already been passed are rejected as out of sequence.

The full wire format — every field, every reply, and the retry rules — is in
[docs/workspace-agent-protocol.md](../workspace-agent-protocol.md).

Shutdown covers both sockets: `Ctrl-C` and SIGTERM stop the message receiver and the status
receiver together, and `run` joins the status thread before exiting.

## Concurrent message handling

Each inbound message is dispatched on its own thread. Two messages that arrive at the same time — whether from the same receiver or different ones — are processed independently and in parallel. A slow handler (tmux subprocess, workspace run, AppleScript) does not block delivery or processing of the next message.

## Signal handling

`Ctrl-C` (SIGINT) and SIGTERM both call `stop` on the message receiver, allowing it to shut down cleanly. No partial writes or dangling socket files are left behind.

## Examples

Start all modes (default):

```bash
work-coordinator run
```

Explicitly enable all modes:

```bash
work-coordinator run --mode all
```

Local socket only:

```bash
work-coordinator run --mode local
```

Messages.app polling only:

```bash
WC_RECIPIENT=+1XXXXXXXXXX work-coordinator run --mode messages
```

Both modes via comma-separated list:

```bash
WC_RECIPIENT=+1XXXXXXXXXX work-coordinator run -m local,messages
```

Both modes via repeated flag:

```bash
WC_RECIPIENT=+1XXXXXXXXXX work-coordinator run -m local -m messages
```

Enable debug output:

```bash
work-coordinator run --debug
```

Debug with local socket only:

```bash
work-coordinator run --debug --mode local
```

Custom socket path:

```bash
WC_SOCKET=/var/run/wc.sock work-coordinator run --mode local
```

## Workflow

`run` belongs in the middle of the standard flow:

1. `register` — create the work item, receive a UUID
2. `start <uuid>` — activate the item (requires the tmux pane to be live)
3. `run` — start the daemon listening for inbound messages
4. `send 'REF body'` — route a message into the tmux pane (local mode)

Keep `run` running in a dedicated terminal for the lifetime of the session.

## Message routing

Every inbound message takes one of two paths depending on whether it matches a known work item.

### Work item routing

`RouteMessage` handles messages that reference a registered work item. Two patterns are recognized:

**Explicit reference prefix** — `REF body` routes to the work item with that external reference:

```
MS-123 go ahead and deploy
```

**Reply prefix** — `reply: instruction` answers an item that is waiting for a human. The target is
either named explicitly (`reply: WC-42 use Postgres`) or left implicit, in which case exactly one
item may be waiting:

```
reply: investigate, debug, fix
```

The agent receives the instruction with the notification that prompted it prepended as context:

```
Current instruction: investigate, debug, fix
Context: [MS-123] CI failed on branch main
```

The `reply:` prefix is case-insensitive. See [send](send.md) for the full set of outcomes,
including what happens when nothing is waiting or several items are.

**Delivery target.** Once a work item is resolved, delivery depends on whether its workspace has a
registered agent. Registered workspaces get the body as an `inject` message over the agent's own
socket — a mid-pipeline steer the agent reads itself. Everything else is typed into the tmux pane
as keystrokes.

### AI command dispatch (messages mode only)

In `messages` mode, any `ai: ` message that does not match a work item ref is dispatched through one of two paths: a **query** that returns information, or an **action** that runs instructions in a workspace.

#### Queries

Query messages return a plain-text reply via iMessage and do not touch any tmux pane. The body is matched against a set of reserved keywords:

| Message | What it returns |
|---------|----------------|
| `ai: help` or `ai: /help` | Overview of ai: syntax and all query keywords |
| `ai: help commands` or `ai: /help commands` | List of all CLI commands with descriptions |
| `ai: help slash` or `ai: /help slash` | Reference for all slash command verbs |
| `ai: help <cmd>` or `ai: /help <cmd>` | Usage summary for one command (fuzzy match) |
| `ai: aliases` | All configured workspace aliases |
| `ai: config` | Current config settings |
| `ai: status` | All work items with state and phase |
| `ai: status <state>` | Work items filtered to one state (fuzzy match) |
| `ai: blocked` | Shorthand for `status blocked` |
| `ai: waiting` | Shorthand for `status waiting_for_human` |
| `ai: active` | Shorthand for `status active` |
| `ai: item REF` | Full detail for one work item by external reference |
| `ai: recent [n]` | Last N events across all work items (default 5) |
| `ai: panes` | Active tmux panes correlated to work items |
| `ai: leases` | Active resource leases |

#### Actions

Action messages run instructions in a workspace tmux pane. Two formats are supported:

```
ai: VERB WORKSPACE - instructions
ai: /verb WORKSPACE [args]
```

| Verb | Behavior |
|------|----------|
| `claude` | Deliver instructions directly to pane 1 of the named workspace session. Acks "Sent to WORKSPACE" on success. |
| `main` | Alias for `claude`. Same behavior. |
| `new` | _(not yet implemented)_ Intended to spawn a new pane via `workspace run WORKSPACE '...' --split --wait --close`. Falls through to the LLM extraction pipeline today. |
| `bash` | _(not yet implemented)_ Intended to spawn a new bash pane via `workspace run`. Falls through to the LLM extraction pipeline today. |
| _(omitted)_ | No verb: use the LLM extraction pipeline. |

**Slash shorthand** delivers to the main session using a compact format — no dash or `instructions` keyword needed. `ai: /help slash` lists all verbs. Examples: `ai: /build MS add OAuth`, `ai: /test MS`, `ai: /stop MS`. Slash routing can be disabled globally by setting `slash_commands_enabled: false` in `~/.config/work-coordinator/config.yml`.

**Every dispatched slash command is registered as a work item** before it is forwarded. The
coordinator allocates the next free `WC-N` reference (`WC-1`, `WC-2`, …), records the command text
as the title with kind `adhoc`, and passes the reference along with the instructions. That
reference is what the workspace agent quotes in its status reports and what you name in a
`reply:`. You do not run `register` for these — see [register](register.md).

**`claude` and `main` bypass the LLM.** No `workspace run` is invoked. The instruction text is
sent as-is to the first pane (pane 1 in domain terms, tmux pane index 0) of window 0 in the named
session. If the session or pane does not exist, an error is returned via iMessage and nothing is
delivered to tmux.

Examples:

```
ai: claude MS - add input validation to the registration form
ai: main my-service - investigate the memory leak
```

**`new`, `bash`, and verb-omitted** use the full dispatch pipeline:

1. If the instruction contains a GitHub URL (`https://github.com/OWNER/REPO/...`), the repo name is extracted and used as the keyword directly — no AI call needed
2. Otherwise `claude -p` extracts a workspace keyword from the instruction text
3. For GitHub URL inputs, `workspace list --all` retrieves all projects (active and dormant); for plain-text inputs, `workspace list` retrieves only active projects
4. The keyword is resolved via alias lookup, then fuzzy-matched against project names — hyphens and underscores are treated as equivalent, so `experimentation-service` matches `experimentation_service`
5. If no match is found, `send-message` notifies you immediately and stops. If the match is a dormant workspace, behavior depends on `auto_launch_workspace` (see below)
6. `workspace run <project> '<instruction>' --split --wait --close` runs the instruction
7. `claude -p` summarizes the output in 1–3 sentences
8. `send-message` delivers the summary back to you

Example — send this iMessage:

```
ai: add input validation to the registration form
```

The daemon extracts a workspace keyword, matches it to an active workspace, runs the instruction
there, and texts you a summary when it finishes.

#### Coordinator commands

Two slash commands act on the coordinator process itself rather than on a workspace. They take no
arguments, and they also accept the bare verb (`ai: restart` is the same as `ai: /restart`).

##### `/restart`

Replaces the running coordinator process with a fresh one via `exec`, so code changes already on
disk take effect. You get an ack before the hand-off and a confirmation after the new process
boots:

```
ai: /restart
→ Restarting...
→ Restarted successfully.
```

If `exec` itself fails, the coordinator retries up to three times, five seconds apart, reporting
each attempt. When the retries run out it sends `Retries exhausted. Manual intervention required.`
and exits with status 1.

##### `/update`

Pulls the coordinator's own checkout, reports what changed, then restarts:

```
ai: /update
→ Updated: 3 commits, now at abc1234 (tag: v1.0.0)
→ Restarting...
→ Restarted successfully.
```

When there is nothing to pull the report reads `Already up to date at <sha>` and the restart still
happens — you asked for one.

**Dirty-tree caveat.** If the checkout has uncommitted changes, `/update` refuses outright:

```
ai: /update
→ Cannot update: working tree has local changes.
```

Nothing is pulled and nothing is restarted. Commit or stash the changes and try again. A failed
pull short-circuits the same way, reporting `Update failed: <git stderr>`.

**Exec success is not boot success.** `exec` only raises when the program cannot be started at all
(`ENOENT`, `EACCES`). If the new process starts and *then* dies during boot — the likely failure
after an `/update` that changes the `Gemfile`, giving `Bundler::GemNotFound` — `exec` already
reported success, no retry fires, and nobody is notified. The daemon is simply gone. The retry loop
guards the unlikely failure, not the likely one; catching the latter needs external supervision
(launchd, a tmux respawn hook) and is out of scope for the coordinator itself.

## Auto-launch configuration

When a GitHub URL is dispatched and the matched workspace is not currently running, the coordinator can launch it automatically before routing the instruction.

| Config key | Default | Description |
|------------|---------|-------------|
| `auto_launch_workspace` | `false` | When `true`, automatically runs `workspace launch <project>` for dormant workspaces found via URL dispatch. Has no effect on plain-text AI dispatch. |
| `workspace_launch_timeout_seconds` | `20` | How long (in seconds) to wait for the launched workspace to appear in `workspace list` before giving up and sending a timeout notification. |

Example config (`~/.config/work-coordinator/config.yml`):

```yaml
auto_launch_workspace: true
workspace_launch_timeout_seconds: 30
```

When `auto_launch_workspace` is `false` (the default) and a dormant workspace is matched, the coordinator sends you a notification and stops — no launch is attempted. When it is `true` and the workspace does not become active within the timeout, a `:launch_timeout` notification is sent.

## Gotchas

**`WC_RECIPIENT` is required for messages mode.** Without it the container cannot configure the Messages.app adapter. The daemon will start but outbound notifications will fail.

**Full Disk Access is required for Messages.app polling.** The process that reads `chat.db` must have FDA granted to the terminal app in System Settings → Privacy & Security → Full Disk Access. After granting FDA, quit and relaunch the terminal and kill any existing tmux server (`tmux kill-server`) before starting a new session — the tmux server inherits permissions at launch, not retroactively.

**Socket path conflicts.** If a stale socket file exists at `WC_SOCKET` from a previous run, the daemon removes it automatically before binding.

**Unknown modes fail fast.** Passing an unrecognized mode value prints an error and exits with status 1 before starting anything.
