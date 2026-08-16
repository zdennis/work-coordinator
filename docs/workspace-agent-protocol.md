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
{"type":"command","workspace":"my-service","work_item_ref":"WC-42","dispatch_id":"d-3f9a1c2e5b7d8a06","body":"add OAuth support","reporting_instructions":"To report status back to the coordinator, run:\n  work-coordinator report --ref WC-42 --type status_update --message \"<message>\"\n  work-coordinator report --ref WC-42 --type task_complete --summary \"<one-line summary>\"\n  work-coordinator report --ref WC-42 --type error --message \"<error detail>\"\nThe status socket is at /tmp/work-coordinator-status.sock (WC_STATUS_SOCKET)."}
```

| Field | Description |
|-------|-------------|
| `type` | `"command"` |
| `workspace` | Workspace name |
| `work_item_ref` | Work item this command belongs to |
| `dispatch_id` | `d-` plus 16 hex characters, unique per delivery |
| `body` | The instruction text |
| `reporting_instructions` | Optional. Rendered string the agent appends to `body` before passing it to the Claude pane. Absent when the coordinator has no template configured. |

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

## Status Reporting Instructions

### Overview

When work-coordinator delivers a `command` to a workspace agent, it can include a
`reporting_instructions` field: a ready-to-use block of text telling Claude (in the tmux pane) how
to send progress reports back. The workspace agent appends this text to the `body` before typing it
into the pane. Claude reads the appended instructions and runs `work-coordinator report` at
appropriate points.

This design keeps the reporting contract in one place (work-coordinator's config), requires no
new configuration on the workspace agent side, and degrades gracefully when the field is absent.

### `reporting_instructions` field

`reporting_instructions` is an optional string field on the `command` payload. When present, the
workspace agent appends it to the body with a double newline separator before sending to the tmux
pane:

```
<original body>

<reporting_instructions>
```

When absent (older coordinator, or template not configured), the agent sends the body unchanged.
No agent-side feature flag or version check is needed.

### How work-coordinator generates the field

work-coordinator renders `reporting_instructions` from a template defined in `config.yml`. The
template key is `status_reporting_template`. When the key is absent or empty, the field is omitted
from the `command` payload entirely.

Substitution variables (Ruby `%{name}` format):

| Variable | Value |
|----------|-------|
| `%{work_item_ref}` | The work item ref for this command (e.g. `WC-42`) |
| `%{status_socket}` | Path to the status socket (default `/tmp/work-coordinator-status.sock`) |
| `%{cli_command}` | The base CLI invocation (default `work-coordinator`) |

Default template (used when `status_reporting_template` is not set in config):

```
none
```

The field is opt-in: it is only sent when `status_reporting_template` is explicitly set. This
avoids appending unsolicited text to every command for users who have not opted into status
reporting.

Example config:

```yaml
status_reporting_template: |
  To report your progress on %{work_item_ref} back to the coordinator, run:
    %{cli_command} report --ref %{work_item_ref} --type status_update --message "<brief note>"
    %{cli_command} report --ref %{work_item_ref} --type task_complete --summary "<one-line summary>"
    %{cli_command} report --ref %{work_item_ref} --type error --message "<error detail>"
  The status socket is %{status_socket} (override with WC_STATUS_SOCKET).
  Report status_update at meaningful milestones. Report task_complete when the work is done.
  Report error only when you cannot proceed.
```

### `work-coordinator report` command

Claude (in the tmux pane) invokes this command to send a status message to the coordinator's status
socket. It writes a single JSON message and exits.

**Synopsis:**

```
work-coordinator report --ref <ref> --type <type> [type-specific flags] [--workspace <name>] [--socket <path>]
```

**Common flags:**

| Flag | Required | Default | Description |
|------|----------|---------|-------------|
| `--ref` | yes | — | Work item ref (e.g. `WC-42`) |
| `--type` | yes | — | Message type (see table below) |
| `--workspace` | no | `$WC_WORKSPACE`, then error | Workspace name |
| `--socket` | no | `$WC_STATUS_SOCKET`, then `/tmp/work-coordinator-status.sock` | Status socket path |

**Type-specific flags:**

| `--type` | Additional required flags |
|----------|--------------------------|
| `status_update` | `--message <text>` |
| `phase_change` | `--phase <name>` |
| `pipeline_advanced` | `--from-pane <n>` and `--to-pane <n>` |
| `task_complete` | `--summary <text>` |
| `error` | `--message <text>` |

**Examples:**

```sh
work-coordinator report --ref WC-42 --type status_update --message "cloned repo, installing deps"
work-coordinator report --ref WC-42 --type phase_change --phase implementing
work-coordinator report --ref WC-42 --type pipeline_advanced --from-pane 1 --to-pane 2
work-coordinator report --ref WC-42 --type task_complete --summary "OAuth added, 12 specs green"
work-coordinator report --ref WC-42 --type error --message "bundle install failed: Gemfile.lock conflict"
```

**JSON sent to the status socket:**

The command constructs the common envelope plus the type-specific fields and writes it as a single
JSON line. `workspace` is filled from `--workspace` or `$WC_WORKSPACE`. `message_id` is a fresh
random identifier. `sequence` is omitted (the coordinator accepts messages without it).

```json
{"type":"status_update","workspace":"my-service","work_item_ref":"WC-42","message_id":"m-9a3f1c","message":"cloned repo, installing deps"}
```

**Exit codes:**

| Code | Meaning |
|------|---------|
| 0 | Coordinator replied `{"ok":true}` |
| 1 | Socket missing, connection refused, coordinator replied `ok:false`, or malformed reply |

On failure the command writes the error to stderr and exits 1. On `terminal_state` (the item is
already complete or abandoned) it prints the coordinator's `action` field so Claude knows to stop
the pipeline.

### Workspace agent: where the append happens

In `handle_command` (agent.rb:264), the body is sent to the first pipeline stage's pane or to
pane 1. The append happens immediately before `@tmux.send_keys`, by assembling the final text:

```ruby
text = message["body"]
if message["reporting_instructions"] && !message["reporting_instructions"].empty?
  text = "#{text}\n\n#{message["reporting_instructions"]}"
end
@tmux.send_keys(@current_name, pane_target(stage[:pane_index]), text)
```

Both branches in `handle_command` (pipeline and default-pane) apply the same append. The field is
read from the parsed message hash and needs no new parsing: `handle_command` already has
`message["body"]`, so `message["reporting_instructions"]` follows the same pattern.

## Human notifications from status reports

The coordinator notifies the human when it receives certain status types. Notifications are
one-way informational messages — they do not park the work item waiting for a reply, and Claude
does not need to do anything in response.

| Type | Human notified? | State change | Message format |
|------|-----------------|--------------|----------------|
| `status_update` | yes | none | `[WC-42] <message>` |
| `phase_change` | yes | phase field updated | `[WC-42] phase: <phase>` |
| `pipeline_advanced` | no | none | (internal; too noisy) |
| `task_complete` | yes (via `CompleteWorkItem`) | → `completed` | `[WC-42] Done — <summary>` |
| `error` | yes (via `NotifyHuman`) | → `waiting_for_human` | `[WC-42] <message>\nReply: WC-42 <your response>` |

**`status_update` and `phase_change`** send a notification without touching the work item's state.
The agent is still running; the human gets a progress ping but is not expected to reply.

**`error`** uses the existing `NotifyHuman` path, which parks the work item as
`waiting_for_human`. The human must reply before the work item can receive another inject or be
completed.

**`task_complete`** is fully handled by `CompleteWorkItem`, which already sends `[ref] Done —
<summary>` and transitions the item to `completed`. No changes needed.

**`pipeline_advanced`** does not notify — it records an internal event that the pipeline moved
between panes. Surfacing this as a human notification would be noisy with no actionable content.

### New use case: `InformHuman`

`status_update` and `phase_change` cannot use `NotifyHuman` because that use case parks the work
item as `waiting_for_human`. Instead, they use a new `InformHuman` use case:

```ruby
# lib/work_coordinator/application/inform_human.rb
InformHuman.new(message_sender:, event_store:).call(work_item_id:, body:)
```

`InformHuman#call`:
1. Looks up the work item to get its external reference.
2. Sends `"[#{ref}] #{body}"` via `message_sender` (no reply hint, no state transition).
3. Appends a `system.informed` event with `{ ref:, body: }`.
4. Returns the work item unchanged.

`WorkspaceStatusReceiver` is wired with both `notify_human:` and `inform_human:`. The `error`
handler keeps using `notify_human`; `status_update` and `phase_change` call `inform_human`.

### `WorkspaceStatusReceiver` handler changes

```ruby
# handle_status_update: append event AND inform human
def handle_status_update(message, work_item)
  append(work_item, "agent.status_update", message, message: message["message"])
  @inform_human.call(work_item_id: work_item.id, body: message["message"])
end

# handle_phase_change: update phase AND inform human
def handle_phase_change(message, work_item)
  @work_item_repo.save(work_item.with(phase: message["phase"], updated_at: Time.now))
  append(work_item, "agent.phase_changed", message, phase: message["phase"])
  @inform_human.call(work_item_id: work_item.id, body: "phase: #{message["phase"]}")
end
```

`handle_pipeline_advanced` and the `task_complete` / `error` handlers are unchanged.

## See also

- [run](commands/run.md) — starting the coordinator and its two sockets
- [send](commands/send.md) — the `reply:` path that produces an `inject`
- [register](commands/register.md) — manual work items versus coordinator-issued `WC-N` refs
- [report](commands/report.md) — sending status from a tmux pane back to the coordinator
