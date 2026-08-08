# start

Transitions a registered work item to `active` state and opens the tmux agent session for it.

```
work-coordinator start <work-item-id>
```

`start` looks up the work item by UUID, marks it `active`, and calls `start_session` on the configured agent session adapter — which sends the opening prompt to the associated tmux pane. To receive routed messages the item must have a tmux target registered via `--tmux` when it was created.

## Arguments

| Argument | Description |
|----------|-------------|
| `work-item-id` | UUID of the work item to start, as printed by `register` |

## Output

On success:

```
Started 4b1f9c2a-83de-4e7a-bf10-d1a2c3e4f567 (state: active)
```

Exits 1 with a usage line if the UUID is omitted. Raises a runtime error if no work item matches the given UUID.

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |

## Examples

Start a work item by its UUID:

```bash
work-coordinator start 4b1f9c2a-83de-4e7a-bf10-d1a2c3e4f567
```

Register and immediately start in one pipeline:

```bash
ID=$(work-coordinator register --title 'Fix crash' --kind bug | awk '/^id:/{print $2}')
work-coordinator start $ID
```

## Gotchas

**The tmux pane must be live.** `start` calls `start_session` regardless of whether the pane at the registered target exists. If the pane is gone, the session adapter will fail silently or raise — the work item is still marked `active` in the database either way.

**UUID must be exact.** There is no fuzzy matching. Copy it from the `register` output or from `work-coordinator status`.
