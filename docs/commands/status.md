# status

Lists all registered work items with their UUID, external reference, state, phase, and title.

```
work-coordinator status
```

States are color-coded in terminals that support ANSI color: `active` (green), `waiting_for_human` (yellow), `blocked` (red), `completed` (cyan). Piping or redirecting output disables color automatically.

## Output

When work items exist:

```
ID                                    REF           STATE                  PHASE                   TITLE
----------------------------------------------------------------------------------------------------
4b1f9c2a-83de-4e7a-bf10-d1a2c3e4f567  GE-123        active                 in_progress             Fix login timeout
71380947-2ce7-4799-adbf-be9516583b45  GE-124        waiting_for_human                              Add OAuth support
```

When no work items are registered:

```
No work items.
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |

## Examples

Check what is currently in flight:

```bash
work-coordinator status
```

Watch status refresh every 5 seconds:

```bash
watch -n 5 work-coordinator status
```

Strip color for scripting:

```bash
work-coordinator status | cat
```
