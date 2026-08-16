# work-items

Inspects and manages work items. `work-items` is a verb with subcommands; today the only subcommand is `status`.

```
work-coordinator work-items <subcommand> [options]
```

| Subcommand | Description |
|------------|-------------|
| `status` | Show a table of work items, preceded by a coordinator header |

Running `work-items` with no subcommand, or with one that is not listed above, prints the usage block and exits 1.

## work-items status

```
work-coordinator work-items status [--state STATE] [--project NAME]
```

Prints a header line naming the role this coordinator answers to and whether it is currently running, followed by a table of work items sorted oldest first. Unlike the older `status` command, the UUID column is dropped — the external reference (`WC-22`, `MS-123`) is what you use to address an item, so it leads the table.

The running check is a probe of the socket file at `$WC_SOCKET`; a stale socket file left behind by a killed daemon will still report `running`.

### Options

| Flag | Description |
|------|-------------|
| `--state STATE` | Only show items in this state. Must be one of `created`, `ready`, `active`, `waiting_for_human`, `waiting_for_resource`, `blocked`, `completed`, `abandoned`. An unknown state exits 1 and lists the valid ones. |
| `--project NAME` | Only show items belonging to this project. The value is resolved against project aliases and names with the same resolver `ai:` routing uses, so `MS` and `my-service` both work. A query that matches nothing exits 1. |

### Output

```
Coordinator  role: home  |  status: running
────────────────────────────────────────────────────────────────────────────────────

REF           STATE                 PHASE                    TITLE
────────────────────────────────────────────────────────────────────────────────────
WC-22         active                planning                 research, plan, implement…
WC-23         active                research+planning        then: make sure this is…
```

States are color-coded in terminals that support ANSI color: `active` (green), `waiting_for_human` (yellow), `blocked` (red), `completed` (cyan). Titles longer than 50 characters are truncated with `…`.

When nothing matches the filters, the header still prints and the table body reads:

```
No work items found.
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Socket probed to decide `running` vs `not running` |

## Examples

Everything the coordinator is tracking:

```bash
work-coordinator work-items status
```

Only what is in flight:

```bash
work-coordinator work-items status --state active
```

Only what is blocked on you:

```bash
work-coordinator work-items status --state waiting_for_human
```

Scope to one project:

```bash
work-coordinator work-items status --project MS
```

Refresh every five seconds:

```bash
watch -n 5 work-coordinator work-items status
```

## Over iMessage

When the daemon is running in `messages` mode with slash commands enabled, the same table comes back as a reply to:

```
ai: work-items status
```

`ai: /work-items status` and a bare `ai: work-items` do the same thing — with no subcommand, `status` is assumed. An unrecognized subcommand is ignored rather than guessed at, so nothing is sent back.

Like `restart` and `update`, `work-items` addresses the coordinator itself, not an agent pane. Nothing is typed into tmux and no work item is registered for the command.

## Gotchas

**`--project` does not fall back to the default project.** Omitting the flag lists items from every project plus untagged items, even when a default project is configured.

**`status: running` only means the socket file exists.** It is a file-existence check, not a liveness probe.
