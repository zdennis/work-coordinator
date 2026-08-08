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

## Gotchas

**`WC_RECIPIENT` is required for messages mode.** Without it the container cannot configure the Messages.app adapter. The daemon will start but outbound notifications will fail.

**Full Disk Access is required for Messages.app polling.** The process that reads `chat.db` must have FDA granted to the terminal app in System Settings → Privacy & Security → Full Disk Access. After granting FDA, quit and relaunch the terminal and kill any existing tmux server (`tmux kill-server`) before starting a new session — the tmux server inherits permissions at launch, not retroactively.

**Socket path conflicts.** If a stale socket file exists at `WC_SOCKET` from a previous run, the daemon may fail to bind. Remove it manually: `rm /tmp/work-coordinator.sock`.

**Unknown modes fail fast.** Passing an unrecognized mode value prints an error and exits with status 1 before starting anything.
