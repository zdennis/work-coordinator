# Workspace agent protocol

The wire protocol between the coordinator and a workspace agent — a long-lived process running
inside a workspace that owns its own pipeline and reports on it, rather than being typed at through
a tmux pane.

Both directions speak JSON Lines over Unix domain sockets: one JSON object, no embedded newlines,
terminated by `\n`. Each connection carries exactly one message and is then closed.

## Sockets

| Socket | Owner | Default path | Carries |
|--------|-------|--------------|---------|
| Message socket | coordinator | `/tmp/work-coordinator.sock` (`WC_SOCKET`) | Human messages, plus agent `register` / `deregister` |
| Status socket | coordinator | `/tmp/work-coordinator-status.sock` (`WC_STATUS_SOCKET`) | Agent status reports |
| Agent socket | workspace agent | agent's choice, declared at registration | `command` and `inject` from the coordinator |

The coordinator opens both of its sockets when `run` starts and removes the socket files on
shutdown. The agent's socket path is whatever it reported in its `register` message; the coordinator
stores it in the `workspace_agent_registrations` table and connects to it on demand.

Every message is scoped by two identifiers: `workspace`, the workspace name, and `work_item_ref`,
the work item the message is about. Refs dispatched through slash commands are coordinator-issued
(`WC-1`, `WC-2`, …); refs on manually registered items are whatever `register --ref` was given.

## Coordinator to agent

Both outbound types are written to the agent's own socket.

### `command`

A new unit of work. Fire-and-forget — the agent acknowledges by accepting the write, and the
coordinator reads no reply.

```json
{"type":"command","workspace":"my-service","work_item_ref":"WC-42","dispatch_id":"d-3f9a1c2e5b7d8a06","body":"add OAuth support"}
```

| Field | Description |
|-------|-------------|
| `type` | `"command"` |
| `workspace` | Workspace name |
| `work_item_ref` | Work item this command belongs to |
| `dispatch_id` | `d-` plus 16 hex characters, unique per delivery |
| `body` | The instruction text |

A delivery with no `work_item_ref`, or to a workspace with no registration, never reaches this
path — it is typed into the tmux pane instead.

### `inject`

A mid-pipeline steer: the human's answer to a question the agent asked. Same shape as `command`
plus `interrupt`, and unlike `command` it is a request/reply exchange — the coordinator writes the
line and then reads exactly one line back.

```json
{"type":"inject","workspace":"my-service","work_item_ref":"WC-42","dispatch_id":"d-91b4...","body":"use Postgres","interrupt":false}
```

| Field | Description |
|-------|-------------|
| `interrupt` | `true` asks the agent to break off what it is doing; `false` queues the steer |

The agent replies with `{"ok":true}` on acceptance, or `{"ok":false,"error":"<reason>"}`. The
coordinator treats any `ok: false` as a refused steer: the human is notified, and the work item
stays waiting, because the words never arrived.

## Agent to coordinator

### Registration — on the message socket

`register` claims a workspace and tells the coordinator where to reach the agent.

```json
{"type":"register","workspace_name":"my-service","socket_path":"/tmp/wa-my-service.sock","pipeline":"build","epoch":"wa-7c1f0a93"}
```

| Field | Description |
|-------|-------------|
| `workspace_name` | Workspace being claimed |
| `socket_path` | Where the coordinator should send `command` and `inject` |
| `pipeline` | Name of the pipeline the agent runs |
| `epoch` | Identifier for this agent process's lifetime |

A workspace can be claimed once. Re-registering under the **same** `epoch` is the same process
restarting its listener, and refreshes the stored row. A **different** `epoch` is a second process
and is refused with `{"ok":false,"error":"already_registered"}`; the first agent keeps the
workspace. Otherwise the reply is `{"ok":true}`.

`deregister` releases the claim and takes only the workspace name:

```json
{"type":"deregister","workspace_name":"my-service"}
```

The reply is `{"ok":true}` whether or not a registration existed. After deregistration, deliveries
to that workspace go back to tmux.

**Current state:** the message socket parses and accepts `register` and `deregister` lines — only
these two `type` values get past the parser, anything else is dropped with a warning — but the
`run` loop does not yet hand the parsed message to the registry. Because nothing consumes the
payload yet, the field names above are the registry's own (`workspace_name`, `socket_path`,
`pipeline`, `epoch`) and are not yet pinned down by a consumer. Registrations written directly to
the `workspace_agent_registrations` table are honoured by every other part of the protocol today.

### Status reports — on the status socket

Every status message is a request/reply exchange on the status socket. The common envelope:

| Field | Required | Description |
|-------|----------|-------------|
| `type` | yes | One of the five types below |
| `workspace` | yes | Workspace name |
| `work_item_ref` | yes | Work item the report is about |
| `message_id` | no | Unique per message; enables deduplication |
| `sequence` | no | Monotonically increasing per `(workspace, work_item_ref)` |

| Type | Extra fields | Effect |
|------|--------------|--------|
| `status_update` | `message` | Appends an `agent.status_update` event |
| `phase_change` | `phase` | Sets the work item's phase, appends `agent.phase_changed` |
| `pipeline_advanced` | `from_pane`, `to_pane` | Appends an `agent.pipeline_advanced` event |
| `task_complete` | `summary` | Completes the work item with that summary |
| `error` | `message` | Notifies the human with that message |

Examples:

```json
{"type":"status_update","workspace":"my-service","work_item_ref":"WC-42","message_id":"m-1","sequence":1,"message":"cloned repo, installing deps"}
{"type":"phase_change","workspace":"my-service","work_item_ref":"WC-42","message_id":"m-2","sequence":2,"phase":"implementing"}
{"type":"pipeline_advanced","workspace":"my-service","work_item_ref":"WC-42","sequence":3,"from_pane":1,"to_pane":2}
{"type":"task_complete","workspace":"my-service","work_item_ref":"WC-42","sequence":4,"summary":"OAuth added, 12 specs green"}
{"type":"error","workspace":"my-service","work_item_ref":"WC-42","message":"bundle install failed: Gemfile.lock conflict"}
```

An unrecognized `type` is dropped with a warning and no reply. Malformed JSON is dropped the same
way — an agent waiting on a reply must treat a closed connection as a failed send.

## Status replies

Success:

```json
{"ok":true,"epoch":"wc-1a2b3c4d5e6f7081"}
```

The `epoch` identifies the coordinator's current listener lifetime, and is echoed in every `ok`
reply. A changed epoch means the coordinator restarted: its deduplication and sequence state is
gone, so an agent tracking the epoch can re-send anything it was unsure about without worrying
about ordering rejections.

Failures carry an `action` telling the agent what to do:

| `error` | `action` | Meaning |
|---------|----------|---------|
| `unknown_work_item` | `give_up` | No item with that ref. Also returns `ref`. Nothing the agent retries will fix this. |
| `terminal_state` | `abort_pipeline` | The item is completed or abandoned. Also returns `state`. Stop the pipeline — the work is over. |
| `out_of_sequence` | `drop` | A message with this `sequence` or higher was already accepted for this `(workspace, work_item_ref)`. Also returns `last_sequence`. Discard the message; do not renumber and re-send. |

A message whose `message_id` was already processed gets a plain `{"ok":true}` and is not applied a
second time, so re-sending after an ambiguous failure is safe.

## Retry behavior

The two failure modes of a Unix socket mean different things, and the coordinator treats them
differently.

**`ECONNREFUSED` — socket file exists, nobody is listening.** This is an agent mid-restart: it
still owns the workspace, it just is not up yet. For `command`, the coordinator retries with
backoff at 1, 2, 4, 8, 16, and 32 seconds — a little over a minute in total. If the agent has still
not answered, it raises `DeliveryTimeout` rather than falling back to tmux: a registered agent that
is not answering is a condition a human needs to hear about, not something to paper over by typing
into a pane the agent may still own. For `inject` there is no retry at all — the reply is
`{"ok":false,"error":"agent_unavailable"}`, because a steer is only meaningful while the pipeline it
interrupts is still running.

**`ENOENT` — the socket file is gone.** The agent is not coming back. The coordinator unregisters
the workspace on the spot, so the registry stays honest and the next delivery goes straight to
tmux. `command` is then delivered to the tmux pane; `inject` returns
`{"ok":false,"error":"agent_gone"}`.

Errors the coordinator surfaces from an `inject`:

| `error` | Cause |
|---------|-------|
| `no_registration` | The workspace has no registered agent |
| `agent_gone` | `ENOENT` — socket file missing; the registration was removed |
| `agent_unavailable` | `ECONNREFUSED` — socket present, agent not listening |
| `no_reply` | The agent closed the connection without answering |
| `malformed_reply` | The agent's reply was not valid JSON |

Anything other than `ok: true` leaves the work item waiting and notifies the human.

## See also

- [run](commands/run.md) — starting the coordinator and its two sockets
- [send](commands/send.md) — the `reply:` path that produces an `inject`
- [register](commands/register.md) — manual work items versus coordinator-issued `WC-N` refs
