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
4b1f9c2a-83de-4e7a-bf10-d1a2c3e4f567  MS-123        active                 in_progress             Fix login timeout
71380947-2ce7-4799-adbf-be9516583b45  MS-124        waiting_for_human                              Add OAuth support
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

## iMessage queries

Project-scoped status is available via iMessage when the daemon is running in `messages` mode. These queries go through `HandleQuery` before reaching the dispatcher and return a plain-text reply.

**`ai: status`** — returns work items for the default project, or all work items when no default is set:

```
[GE] 2 work items:
MS-123      active/in_progress        Fix login timeout
MS-124      waiting_for_human         Add OAuth support
```

Without a default project:

```
3 work items:
MS-123      active/in_progress        Fix login timeout
MS-124      waiting_for_human         Add OAuth support
WC-5        completed                 Update README
```

**`ai: status GE`** — returns work items scoped to the project whose alias or name matches `GE`:

```
[GE] 2 work items:
MS-123      active/in_progress        Fix login timeout
MS-124      waiting_for_human         Add OAuth support
```

When the project matches nothing and the filter is also not a known work item state:

```
Unknown state or project: XYZ. Known states: created, active, waiting_for_human, blocked, completed, abandoned
```

When the project filter is ambiguous:

```
Ambiguous: matched GE, GE2. Be more specific.
```

When a project is found but has no work items:

```
[GE] No work items.
```

**`ai: default GE`** — sets `GE` as the default project so that bare `ai: status` scopes to it:

```
Default project set to GE (my-service)
```

To set a default, the project must already exist in the DB. Create one with `work-coordinator project add` before using `ai: default`. Project-scoped status is not available through the CLI `status` command — use `work-coordinator project list` to inspect projects and `work-coordinator status` to list all items.
