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
MS-123 go ahead and deploy
```

**Reply prefix** — `reply: instruction` looks up the most recent outbound notification and routes to that work item with context prepended:

```
reply: investigate, debug, fix
```

The agent receives:

```
Current instruction: investigate, debug, fix
Context: [MS-123] CI failed on branch main
```

The `reply:` prefix is case-insensitive. It always routes to the work item from the most recent `notify` call, regardless of how many work items are registered.

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

**Slash shorthand** delivers to the main session using a compact format — no dash or `instructions` keyword needed. `ai: /help slash` lists all verbs. Examples: `ai: /build GE add OAuth`, `ai: /test GE`, `ai: /stop GE`. Slash routing can be disabled globally by setting `slash_commands_enabled: false` in `~/.config/work-coordinator/config.yml`.

**`claude` and `main` bypass the LLM.** No `workspace run` is invoked. The instruction text is
sent as-is to the first pane (pane 1 in domain terms, tmux pane index 0) of window 0 in the named
session. If the session or pane does not exist, an error is returned via iMessage and nothing is
delivered to tmux.

Examples:

```
ai: claude GE - add input validation to the registration form
ai: main my-service - investigate the memory leak
```

**`new`, `bash`, and verb-omitted** use the full dispatch pipeline:

1. If the instruction contains a GitHub URL (`https://github.com/OWNER/REPO/...`), the repo name is extracted and used as the keyword directly — no AI call needed
2. Otherwise `claude -p` extracts a workspace keyword from the instruction text
3. `workspace list` retrieves the active projects
4. The keyword is resolved via alias lookup, then fuzzy-matched against project names
5. If no match is found, `send-message` notifies you immediately and stops
6. `workspace run <project> '<instruction>' --split --wait --close` runs the instruction
7. `claude -p` summarizes the output in 1–3 sentences
8. `send-message` delivers the summary back to you

Example — send this iMessage:

```
ai: add input validation to the registration form
```

The daemon extracts a workspace keyword, matches it to an active workspace, runs the instruction
there, and texts you a summary when it finishes.

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

**Socket path conflicts.** If a stale socket file exists at `WC_SOCKET` from a previous run, the daemon may fail to bind. Remove it manually: `rm /tmp/work-coordinator.sock`.

**Unknown modes fail fast.** Passing an unrecognized mode value prints an error and exits with status 1 before starting anything.
