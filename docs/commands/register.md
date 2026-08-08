# register

Creates a new work item in the database and returns its UUID.

```
work-coordinator register --title TITLE --kind KIND [options]
```

The item starts in `created` state. Nothing is routed or dispatched — `register` only writes the record. To activate the item and make it eligible for message delivery, run `start <uuid>` next.

## Required flags

| Flag | Description |
|------|-------------|
| `--title TITLE` | Short descriptive title for the work item |
| `--kind KIND` | Type of work item — e.g. `feature`, `bug`, `chore` |

## Optional flags

| Flag | Description |
|------|-------------|
| `--ref REF` | External reference the message router matches against incoming messages (e.g. `BUG-99`). Without this, no message can ever be routed to this item. |
| `--repo REPO` | Repository name or path |
| `--tmux TARGET` | tmux target in `SESSION:WINDOW.PANE` format (e.g. `work:1.0`). The router checks this pane is live before sending a message. Without it, message delivery silently fails. |

## Output

On success, `register` prints the UUID and state:

```
id: 4f3a1c2e-...
state: created
```

## Persistence

Writes to `db/work_coordinator.sqlite3`. Override the path with the `WC_DATABASE` environment variable. The record survives restarts.

## Examples

Minimal registration:

```bash
work-coordinator register --title 'Fix login timeout' --kind bug
```

Full registration linking to an external tracker and a tmux pane:

```bash
work-coordinator register \
  --title 'Add OAuth support' \
  --kind feature \
  --ref 'BUG-42' \
  --repo my-app \
  --tmux work:1.0
```

Capture the UUID and immediately start the item:

```bash
ID=$(work-coordinator register --title 'Refactor auth' --kind chore | awk '/^id:/{print $2}')
work-coordinator start $ID
```

## Workflow

`register` is the first step in the standard flow:

1. `register` — create the item, receive a UUID
2. `start <uuid>` — activate it (requires the tmux pane to be live)
3. `run` — start the daemon listening on the socket
4. `send 'REF body'` — route a message into the tmux pane

Only items in `active` state with a live tmux pane receive routed messages.

## Gotchas

**`--ref` is required for routing.** Without it, `send` has no way to match an incoming message to this item. Register without `--ref` only if you never intend to route messages to the item.

**`--tmux` is required for delivery.** An active item without a tmux target will appear healthy but messages routed to it will be silently dropped.

**`--ref` must match the router's pattern exactly.** The router matches refs using the pattern `[A-Z]+-\d+` (e.g. `BUG-99`, `FEAT-12`). A ref like `#42` will not match and the item will never receive a message.
