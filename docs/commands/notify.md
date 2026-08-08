# notify

Sends a human notification for a work item and transitions it to `waiting_for_human`.

```
work-coordinator notify <work-item-id> "<body>" [options]
```

`notify` sends the body to the configured recipient, prefixed with the work item's external reference so the reply can be routed back. It then moves the item to `waiting_for_human` and records an `agent.question_asked` event. The message format sent to the recipient is:

```
[GE-123] Your question here
Reply: GE-123 <your response>
```

## Arguments

| Argument | Description |
|----------|-------------|
| `work-item-id` | UUID of the work item |
| `"body"` | The notification message to deliver |

## Optional flags

| Flag | Description |
|------|-------------|
| `--mode MODE` | Delivery mode: `messages` (default) or `local`. Use `local` to send over the Unix socket instead of iMessage. |

## Output

On success:

```
Notification sent.
```

Exits 1 with a usage line if either `work-item-id` or `body` is missing. Raises a runtime error if no work item matches the UUID.

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_RECIPIENT` | _(required for messages mode)_ | Phone number or email for the iMessage recipient |
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path used in local mode |
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |

## Examples

Notify via iMessage that a work item needs review:

```bash
work-coordinator notify 4b1f9c2a-83de-4e7a-bf10-d1a2c3e4f567 'PR is ready for review'
```

Notify via local socket instead of iMessage:

```bash
work-coordinator notify 4b1f9c2a-83de-4e7a-bf10-d1a2c3e4f567 'Build failed' --mode local
```

## Gotchas

**`WC_RECIPIENT` must be set for messages mode.** Without it the iMessage adapter has no destination and the send will fail at runtime.

**The work item must have an external reference.** The notification is prefixed with `[REF]` and the reply instructions include the REF. An item registered without `--ref` will produce a malformed message and replies cannot be routed back.

**State transition is unconditional.** `notify` moves the item to `waiting_for_human` regardless of its current state. Calling it on a `completed` or `blocked` item will change its state.
