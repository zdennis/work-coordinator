# run

Starts the coordinator daemon, opens inbound message channels, and routes messages to registered tmux panes.

```
work-coordinator run [options]
```

By default `run` enables all modes — local socket and Messages.app polling — simultaneously. Use `--mode` to restrict to a specific subset.

## Options

| Flag | Description |
|------|-------------|
| `-m`, `--mode MODE` | Receive mode. Repeatable and comma-separated. Valid values: `all`, `local`, `messages`. Defaults to `all`. |

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
| `local` | Opens a Unix domain socket at `WC_SOCKET` (default `/tmp/work-coordinator.sock`) and listens for messages sent via `work-coordinator send`. |
| `messages` | Polls `~/Library/Messages/chat.db` every few seconds for iMessages prefixed with `ai: `. Requires `WC_RECIPIENT` to be set. |

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path used in `local` mode |
| `WC_RECIPIENT` | _(required for messages mode)_ | Phone number or email address for outbound notifications |
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |

## Startup banner

Each enabled mode prints a line when the daemon starts.

Local mode:

```
work-coordinator running on /tmp/work-coordinator.sock (local socket)
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
work-coordinator running on /tmp/work-coordinator.sock (local socket)
work-coordinator running in messages mode (polling ~/Library/Messages/chat.db)
Listening for messages starting with: ai:
Press Ctrl-C to stop.
```

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
GE-123 go ahead and deploy
```

**Reply prefix** — `reply: instruction` looks up the most recent outbound notification and routes to that work item with context prepended:

```
reply: investigate, debug, fix
```

The agent receives:

```
Current instruction: investigate, debug, fix
Context: [GE-123] CI failed on branch main
```

The `reply:` prefix is case-insensitive. It always routes to the work item from the most recent `notify` call, regardless of how many work items are registered.

### AI command dispatch (messages mode only)

In `messages` mode, any `ai: ` message that does not match a work item ref is dispatched through one of two paths: a **query** that returns information, or an **action** that runs instructions in a workspace.

#### Queries

Query messages return a plain-text reply via iMessage and do not touch any tmux pane. The body is matched against a set of reserved keywords:

| Message | What it returns |
|---------|----------------|
| `ai: help` | Overview of ai: syntax and all query keywords |
| `ai: help commands` | List of all CLI commands with descriptions |
| `ai: help <cmd>` | Usage summary for one command (fuzzy match) |
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

Action messages run instructions in a workspace tmux pane. The format is:

```
ai: [verb] WORKSPACE - instructions
```

The verb and workspace name can appear in either order:

```
ai: claude GE - add input validation to the registration form
ai: GE claude - add input validation to the registration form
```

| Verb | Behavior |
|------|----------|
| `claude` _(or omitted)_ | Send instructions to the default pane for the workspace |
| `new` | Split a new pane and run instructions there |
| `bash` | Split a new bash pane and run instructions there |

When no verb is given, the pipeline is:

1. `claude -p` extracts a workspace keyword from the instruction text
2. `workspace list` retrieves the active projects
3. The keyword is resolved via alias lookup, then fuzzy-matched against project names
4. If no match is found, `send-message` notifies you immediately and stops
5. `workspace run <project> '<instruction>' --split --wait --close` runs the instruction in that project's tmux session
6. `claude -p` summarizes the output in 1–3 sentences
7. `send-message` delivers the summary back to you

Example — send this iMessage:

```
ai: add input validation to the registration form
```

The daemon extracts a workspace keyword, matches it to an active workspace, runs the instruction there, and texts you a summary when it finishes.

## Gotchas

**`WC_RECIPIENT` is required for messages mode.** Without it the container cannot configure the Messages.app adapter. The daemon will start but outbound notifications will fail.

**Full Disk Access is required for Messages.app polling.** The process that reads `chat.db` must have FDA granted to the terminal app in System Settings → Privacy & Security → Full Disk Access. After granting FDA, quit and relaunch the terminal and kill any existing tmux server (`tmux kill-server`) before starting a new session — the tmux server inherits permissions at launch, not retroactively.

**Socket path conflicts.** If a stale socket file exists at `WC_SOCKET` from a previous run, the daemon may fail to bind. Remove it manually: `rm /tmp/work-coordinator.sock`.

**Unknown modes fail fast.** Passing an unrecognized mode value prints an error and exits with status 1 before starting anything.
