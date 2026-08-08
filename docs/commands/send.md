# send

Sends a raw message to the running coordinator over its Unix socket.

```
work-coordinator send "REF body"
```

The message is delivered over the socket to the `run` daemon, which routes it to the tmux pane of the matching work item. The REF must match the `--ref` registered with the work item exactly (case-sensitive, e.g. `GE-123`). The daemon strips the REF and delivers only the body to the pane.

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
Sent: GE-123 yes, go ahead
```

Exits 1 with a usage line if the message is empty. Exits 1 with an error message if the socket connection fails (daemon not running or wrong path).

## Examples

Signal that a work item is blocked:

```bash
work-coordinator send 'GE-123 blocked: waiting on API keys'
```

Mark a work item as completed:

```bash
work-coordinator send 'GE-123 done'
```

Send via a custom socket path:

```bash
WC_SOCKET=/var/run/wc.sock work-coordinator send 'GE-123 update: tests passing'
```

## Gotchas

**The `run` daemon must be running.** `send` connects to the socket immediately; if nothing is listening, the command fails with a connection error.

**REF must match exactly.** The router uses `[A-Z]+-\d+` to extract the reference prefix. A mismatch — wrong case, extra characters, or a non-matching format — results in an "Unrouted message" log in the daemon and nothing delivered to the pane.

**Socket path must match between `send` and `run`.** If `run` was started with a custom `WC_SOCKET`, `send` must use the same value.
