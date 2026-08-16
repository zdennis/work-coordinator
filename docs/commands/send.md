# send

Sends a raw message to the running coordinator over its Unix socket.

```
work-coordinator send "REF body"
```

The message is delivered over the socket to the `run` daemon, which routes it to the tmux pane of the matching work item. The REF must match the `--ref` registered with the work item exactly (case-sensitive, e.g. `MS-123`). The daemon strips the REF and delivers only the body to the pane.

## Arguments

| Argument | Description |
|----------|-------------|
| `"REF body"` | Full message string. REF identifies the work item; body is what gets delivered to the pane. |

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path that the daemon is listening on |

## Output

On success:

```
Sent: MS-123 yes, go ahead
```

Exits 1 with a usage line if the message is empty. Exits 1 with an error message if the socket connection fails (daemon not running or wrong path).

## Replies

A message beginning with `reply:` (case-insensitive) answers an item that is waiting for a human,
rather than addressing one by prefix. The target is named explicitly or left implicit.

**Explicit reference** — `reply: WC-42 use Postgres` routes to `WC-42`:

```bash
work-coordinator send 'reply: WC-42 use Postgres'
```

**Bare reply** — with no reference, the coordinator looks at every item currently waiting for a
human. If exactly one is waiting, the reply goes there:

```bash
work-coordinator send 'reply: use Postgres'
```

The outcomes:

| Situation | What happens |
|-----------|--------------|
| Exactly one item waiting | Routed to that item |
| Nothing waiting | Refused — `Nothing is waiting for a reply right now.` |
| Several items waiting | Refused, listing the waiting refs and the `reply: REF ...` form to use |
| Named ref unknown | Refused — `<REF> is not a work item I know about.` |
| Named ref not waiting | Refused, saying whether it is finished, abandoned, or in some other state |

A refusal is reported back to you and nothing is delivered. The item stays waiting, so the question
it asked is still open.

**Context is prepended.** When the item has a prior notification, the agent receives the reply with
that notification quoted:

```
Current instruction: use Postgres
Context: [WC-42] Which datastore should this use?
```

**Registered agents get an inject, not keystrokes.** If the target item's workspace has a
registered workspace agent, the reply is forwarded over that agent's socket as an `inject`
message — a mid-pipeline steer the agent reads itself — instead of being typed into a tmux pane.
There is no tmux fallback for this path and no retry: a steer only means something while the
pipeline it interrupts is still running. If the agent is gone or not answering, the reply is
refused, you are notified, and the item stays waiting. See
[docs/workspace-agent-protocol.md](../workspace-agent-protocol.md).

## Examples

Signal that a work item is blocked:

```bash
work-coordinator send 'MS-123 blocked: waiting on API keys'
```

Mark a work item as completed:

```bash
work-coordinator send 'MS-123 done'
```

Answer the one item that is waiting:

```bash
work-coordinator send 'reply: yes, ship it'
```

Answer a specific item when several are waiting:

```bash
work-coordinator send 'reply: WC-42 use Postgres'
```

Send via a custom socket path:

```bash
WC_SOCKET=/var/run/wc.sock work-coordinator send 'MS-123 update: tests passing'
```

## Gotchas

**The `run` daemon must be running.** `send` connects to the socket immediately; if nothing is listening, the command fails with a connection error.

**REF must match exactly.** The router uses `[A-Z]+-\d+` to extract the reference prefix. A mismatch — wrong case, extra characters, or a non-matching format — results in an "Unrouted message" log in the daemon and nothing delivered to the pane.

**Socket path must match between `send` and `run`.** If `run` was started with a custom `WC_SOCKET`, `send` must use the same value.
