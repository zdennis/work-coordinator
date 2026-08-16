# Handling coordinator restarts

A guide for workspace agent implementors. It explains what happens when work-coordinator restarts
itself, what the coordinator tells you before it does, and how an agent should behave so a restart
is invisible to the pipeline it is running.

## Why this matters

The coordinator restarts to pick up an updated build. Restarting closes both of its Unix sockets —
the message socket and the status socket — and reopens them in the replacement process. For the
duration of the gap, usually well under a second, any write to the status socket fails with
`ECONNREFUSED`.

An agent that treats that failure as fatal will abort a healthy pipeline over an event that resolves
itself in under a second. An agent that ignores it silently loses the status report. Neither is what
you want, so the coordinator gives you advance notice.

## The `coordinator_restart` message

Immediately before the coordinator `exec`s its replacement, it writes one line to each registered
agent's socket:

```json
{"type":"coordinator_restart","dispatch_id":"d-3f9a1c2e"}
```

| Field | Description |
|-------|-------------|
| `type` | Always `"coordinator_restart"` |
| `dispatch_id` | Unique identifier for this notification |

It arrives on the same socket as `command` and `inject`, so it is handled in the same dispatch
switch. Unlike `inject`, **no reply is read** — the coordinator writes the line and proceeds to
`exec`. Do not block waiting to send one; you will only delay your own handling.

## Recommended handling

1. **Enter a coordinator-unavailable window.** On receipt of `coordinator_restart`, set a flag and
   record the time. While the flag is set, assume the status socket is down.

2. **Buffer outbound status reports.** Any `work-coordinator report` call or direct status socket
   write made during the window goes into an in-memory queue instead of the socket. Keep them in
   the order they were produced — the coordinator's sequence checking depends on it.

3. **Poll for the socket to come back**, with exponential backoff: 1, 2, 4, 8, 16 seconds. A poll
   succeeds when a connection to the status socket path is accepted.

4. **Flush on reconnect.** Send the buffered reports in order, then clear the flag and resume normal
   operation.

5. **Give up after about 30 seconds.** If the coordinator has not returned by then, log a warning,
   discard the buffer, and carry on. Those reports are lost, but work item state lives in the
   coordinator's database, not in your queue — the item is still there when the coordinator returns.

## Fallback when there is no advance warning

`coordinator_restart` is a courtesy, not a guarantee. A coordinator killed abruptly, or one whose
write to your socket fails, sends nothing at all. So your `ECONNREFUSED` handling on the status
socket must already be graceful on its own: retry with the same backoff rather than failing the
pipeline. Treat `coordinator_restart` purely as an early signal that makes an otherwise surprising
failure expected.

## Re-registering after a restart

The coordinator clears the workspace agent registry on every boot. After a restart, your
registration is gone, and deliveries to your workspace fall back to being typed into the tmux pane
until you register again.

So re-register as soon as you detect the coordinator is back. Two ways to detect it:

- **The `epoch` in a status reply changed.** Every `{"ok":true}` on the status socket carries the
  coordinator's `epoch`. A value different from the one you last saw means a new coordinator
  process.
- **Poll the message socket** with your `register` message until it succeeds.

Re-register with the **same** `epoch` you first used — it identifies your process lifetime, and
reusing it tells the coordinator this is the same agent, not a second one claiming the workspace.

## Example flow

1. Agent is mid-pipeline on `WC-42`, registered for workspace `my-service`.
2. Coordinator writes `{"type":"coordinator_restart","dispatch_id":"d-3f9a1c2e"}` to the agent
   socket and `exec`s.
3. Agent sets its unavailable flag and starts the backoff timer. No reply is sent.
4. The pipeline finishes a stage and wants to send `status_update` — it goes into the buffer.
5. At t+1 s the agent tries the status socket: `ECONNREFUSED`. At t+2 s it tries again and connects.
6. Agent flushes the buffered `status_update`. The reply carries a new `epoch`.
7. The changed `epoch` tells the agent the registry was cleared, so it re-sends `register` on the
   message socket with its original `epoch` and gets `{"ok":true}`.
8. Normal operation resumes; the pipeline never noticed.

## See also

- [workspace agent protocol](workspace-agent-protocol.md) — the full wire protocol
- [run](commands/run.md) — starting the coordinator and its two sockets
