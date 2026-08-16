# Implementation Plan: Status Reporting Instructions (work-coordinator)

## Overview

Today a workspace agent can send status reports to the coordinator's status socket, but nothing
tells Claude — running inside the workspace's tmux pane — that this channel exists or how to use it.
This change closes that loop. The coordinator renders an operator-configured instruction block at
delivery time and ships it on the `command` payload as `reporting_instructions`; the workspace agent
appends it to the body before typing it into the pane. Claude then reports progress by invoking a
new thin CLI client, `work-coordinator report`, which writes one JSON line to the status socket and
exits. On the receiving side, `status_update` and `phase_change` gain human notifications through a
new `InformHuman` use case, and `error` moves off `NotifyHuman` onto `InformHuman` too — an agent
error is an announcement, not a question, and parking the item solicits a reply that would be
injected into a pipeline that has already stopped.

The feature is entirely opt-in: with no `status_reporting_template` configured, the field is omitted
and behavior is unchanged.

---

## Changes

Numbered in dependency order. Implement and spec each before moving to the next.

### 1. Config: `status_reporting_template` and `status_reporting_cli`

**File:** `lib/work_coordinator/config.rb`

Add two plain readers alongside the existing ones (near `instruction_context`, line 74):

```ruby
DEFAULT_STATUS_REPORTING_CLI = "work-coordinator"

# Template rendered into the `reporting_instructions` field of a `command`
# payload. Nil when unset — the field is then omitted entirely.
def status_reporting_template
  data.fetch("status_reporting_template", nil)
end

# Base CLI invocation substituted as %{cli_command}. Configurable because a
# checkout runs `bin/work-coordinator`, not the installed binary.
def status_reporting_cli
  data.fetch("status_reporting_cli", DEFAULT_STATUS_REPORTING_CLI)
end
```

**Do not** add a `render_reporting_instructions` method here. `Config` stays a YAML reader; it must
not know the status socket path (the container resolves that) and must not read `ENV`. Rendering
lives in `WorkspaceAgentSession` (change 3).

**`default_content`** (line 150): add commented examples after the
`workspace_launch_timeout_seconds` line, before `aliases:`. Note the labeled separator on the first
line — `\n\n` alone is weak framing when the block is glued onto an arbitrary task body:

```yaml
# status_reporting_cli: work-coordinator  # Base CLI invocation used in status reporting instructions
# status_reporting_template: |
#   --- Status reporting ---
#   You are working on %{work_item_ref} in workspace %{workspace}. Report progress by running:
#     %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type status_update --message "<brief note>"
#     %{cli_command} report --ref %{work_item_ref} --workspace %{workspace} --type error --message "<error detail>"
#   The status socket is %{status_socket}.
#   Report status_update at meaningful milestones. Report error only when you cannot proceed.
```

Note the example deliberately omits `task_complete` — see change 3 for why, and the
`%{task_complete_line}` variable that fills it in where it is safe.

---

### 2. Registry: confirm the pipeline flag is available (mostly no-op)

**File:** `lib/work_coordinator/adapters/sqlite_workspace_agent_registry.rb`

`register` already accepts `pipeline:` and persists it, and `find` already returns it in the entry
hash (`{socket_path:, pipeline:, epoch:}`, line 50). **No code change is required here.**

What the implementer must know:

- `pipeline` is the pipeline *name* (a string), not a boolean. Treat "has a pipeline" as
  `pipeline` being a non-nil, non-empty string.
- `Adapters::FakeWorkspaceAgentRegistry` must return `pipeline` in its `find` result too — check it
  and add the key if missing, or the specs in change 3 cannot exercise both branches.
- Per `docs/workspace-agent-protocol.md`, the message socket parses `register` but does not yet hand
  the payload to the registry. Rows written directly to `workspace_agent_registrations` are honoured.
  This plan does not change that; it only consumes the column.

---

### 3. WorkspaceAgentSession: render and attach `reporting_instructions`

**File:** `lib/work_coordinator/adapters/workspace_agent_session.rb`

**Constructor** — add two keywords (both defaulted so existing specs keep constructing it):

```ruby
def initialize(tmux:, registry:, sleeper: ->(seconds) { sleep(seconds) },
               logger: Logger.new(IO::NULL), tmux_fallback_enabled: true,
               status_socket_path: "/tmp/work-coordinator-status.sock",
               config: nil)
  # ...
  @status_socket_path = status_socket_path
  @config = config
end
```

**`deliver`** (line 50) — pass the registry entry's pipeline through to delivery:

```ruby
deliver_to_agent(
  socket_path: entry[:socket_path],
  workspace: session_id,
  work_item_ref: work_item_ref,
  body: message,
  pipeline: entry[:pipeline]
)
```

**`deliver_to_agent`** (line 118) — merge the rendered block into the payload *here*, not in
`payload()`. `payload()` is shared with `inject`, and a steer must never carry reporting
instructions:

```ruby
def deliver_to_agent(socket_path:, workspace:, work_item_ref:, body:, pipeline: nil)
  data = payload(type: "command", workspace: workspace, work_item_ref: work_item_ref, body: body)
  instructions = render_reporting_instructions(
    work_item_ref: work_item_ref,
    workspace: workspace,
    has_pipeline: !pipeline.to_s.strip.empty?
  )
  data = data.merge(reporting_instructions: instructions) if instructions
  write_payload(connect(socket_path, workspace), data)
end
```

**New private method:**

```ruby
# Renders the operator's status-reporting template for one delivery.
#
# Returns nil — and the caller omits the field — when no template is
# configured or the template refers to a variable we do not supply.
def render_reporting_instructions(work_item_ref:, workspace:, has_pipeline:)
  template = @config&.status_reporting_template
  return nil if template.nil? || template.strip.empty?

  rendered = format(
    template,
    work_item_ref: work_item_ref,
    workspace: workspace,
    status_socket: @status_socket_path,
    cli_command: @config.status_reporting_cli,
    task_complete_line: task_complete_line(work_item_ref, workspace, has_pipeline)
  )
  rendered.strip.empty? ? nil : rendered
rescue KeyError, ArgumentError => e
  @logger.warn "WorkspaceAgentSession: status_reporting_template failed to render: #{e.message}"
  nil
end

# A pipeline workspace signals completion with its own sentinel. If Claude
# also reports task_complete the item completes early, and the agent's real
# sentinel then fails with terminal_state/abort_pipeline, tearing down a live
# pipeline. So the line is only offered where Claude's report is the only
# completion signal the coordinator will ever get.
def task_complete_line(work_item_ref, workspace, has_pipeline)
  return "" if has_pipeline

  "  #{@config.status_reporting_cli} report --ref #{work_item_ref} " \
    "--workspace #{workspace} --type task_complete --summary \"<one-line summary>\"\n"
end
```

Substitution variables, for the doc and for specs: `%{work_item_ref}`, `%{workspace}`,
`%{status_socket}`, `%{cli_command}`, `%{task_complete_line}`.

`%{workspace}` is required — the rendered command line must carry `--workspace`, because nothing
sets a workspace name in the pane's environment. The name is already in scope at delivery time.

`format` raises `KeyError` on an unknown `%{name}` and `ArgumentError` on malformed format
directives (a bare `%` in the template, for instance). Both are operator config errors, not runtime
faults: log and omit rather than failing the delivery.

---

### 4. Container: wire the new dependencies

**File:** `lib/work_coordinator/container.rb`

`status_socket_path` is currently a local parameter of `#initialize` (line 84) used only at line 104.
Store it so `build_core_adapters!` can use it. Because `build_core_adapters!(modes)` runs at line 101,
assign `@status_socket_path = status_socket_path` before that call (next to `@socket_path =` on
line 93).

**`build_core_adapters!`** (line 116):

```ruby
@agent_session = Adapters::WorkspaceAgentSession.new(
  tmux: tmux,
  registry: @workspace_agent_registry,
  logger: @logger,
  tmux_fallback_enabled: @config.tmux_fallback_enabled?,
  status_socket_path: @status_socket_path,
  config: @config
)
```

**`wire!`** (line 184) — construct `InformHuman` (change 6) next to `NotifyHuman`. It takes only
`message_sender:` and `event_store:`, so it cannot use the `human_deps` splat:

```ruby
@inform_human = Application::InformHuman.new(message_sender: @message_sender, event_store: @event_store)
```

**`build_workspace_status_receiver`** (line 122) — pass `inform_human: @inform_human`. Note
ordering: `build_workspace_status_receiver` is called at line 104, after `wire!` at line 102, so
`@inform_human` is already set.

Add `:inform_human` to the `attr_reader` list (line 61) and a `@!attribute` doc comment alongside
`notify_human`.

---

### 5. `work-coordinator report` — new CLI command

**File:** `bin/work-coordinator`

**`COMMANDS` hash** (line 29) — add after `"notify"`:

```ruby
"report" => "Send a status report to the running coordinator's status socket"
```

**New `when "report"` branch.** This is a thin socket client: it must **not** build a `Container`.
Claude invokes it repeatedly from inside a pane, and opening and migrating the database on every
progress ping is both slow and a write-contention hazard against the running coordinator.

Flags:

| Flag | Required | Default |
|------|----------|---------|
| `--ref REF` | yes | — |
| `--type TYPE` | yes | — |
| `--workspace NAME` | no | `$WC_WORKSPACE`, else omitted from payload |
| `--message TEXT` | for `status_update`, `error` | — |
| `--phase TEXT` | for `phase_change` | — |
| `--summary TEXT` | for `task_complete` | — |
| `--from-pane N` | for `pipeline_advanced` | — |
| `--to-pane N` | for `pipeline_advanced` | — |
| `--socket PATH` | no | `$WC_STATUS_SOCKET`, else `/tmp/work-coordinator-status.sock` |

Sketch:

```ruby
when "report"
  TYPES = %w[status_update phase_change pipeline_advanced task_complete error].freeze
  REQUIRED_FIELDS = {
    "status_update"     => [:message],
    "phase_change"      => [:phase],
    "pipeline_advanced" => [:from_pane, :to_pane],
    "task_complete"     => [:summary],
    "error"             => [:message]
  }.freeze

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: work-coordinator report --ref <ref> --type <type> [options]"
    opts.separator ""
    opts.separator "Send a single status report to the coordinator's status socket and exit."
    opts.separator "Intended to be run by an AI agent from inside a workspace pane."
    opts.separator ""
    opts.separator "Types and their required flags:"
    opts.separator "    status_update      --message"
    opts.separator "    phase_change       --phase"
    opts.separator "    pipeline_advanced  --from-pane and --to-pane"
    opts.separator "    task_complete      --summary"
    opts.separator "    error              --message"
    opts.separator ""
    opts.separator "Examples:"
    opts.separator '  work-coordinator report --ref WC-42 --type status_update --message "installing deps"'
    opts.separator "  work-coordinator report --ref WC-42 --type phase_change --phase implementing"
    opts.separator '  work-coordinator report --ref WC-42 --type error --message "bundle install failed"'
    opts.separator ""
    opts.separator "Options:"
    opts.on("--ref REF", "Work item ref (e.g. WC-42)") { |v| options[:ref] = v }
    opts.on("--type TYPE", TYPES, "Report type: #{TYPES.join(', ')}") { |v| options[:type] = v }
    opts.on("--workspace NAME", "Workspace name (default: $WC_WORKSPACE)") { |v| options[:workspace] = v }
    opts.on("--message TEXT", "Message body") { |v| options[:message] = v }
    opts.on("--phase TEXT", "New phase name") { |v| options[:phase] = v }
    opts.on("--summary TEXT", "One-line completion summary") { |v| options[:summary] = v }
    opts.on("--from-pane N", "Pane the pipeline moved from") { |v| options[:from_pane] = Integer(v) }
    opts.on("--to-pane N", "Pane the pipeline moved to") { |v| options[:to_pane] = Integer(v) }
    opts.on("--socket PATH", "Status socket path") { |v| options[:socket] = v }
    opts.on("-h", "--help", "Print help for this command") { puts opts; exit }
  end.parse!(ARGV)
```

Validation, then send:

- Missing `--ref` or `--type` → `warn "Usage: work-coordinator report --ref <ref> --type <type> ..."`,
  `exit 1`. (`OptionParser`'s type list already rejects an unknown `--type` with its own message.)
- Missing a required type-specific flag → `warn "--type #{type} requires --#{flag}"`, `exit 1`.
- `Integer(v)` in the pane handlers raises `ArgumentError` on garbage; rescue it around `parse!` and
  exit 1 with a readable message. OptionParser yields strings, so the coercion is not optional — the
  protocol's `from_pane`/`to_pane` are numbers.

Payload:

```ruby
payload = { type: options[:type], work_item_ref: options[:ref] }
workspace = options[:workspace] || ENV["WC_WORKSPACE"]
payload[:workspace] = workspace if workspace
REQUIRED_FIELDS.fetch(options[:type]).each { |f| payload[f] = options[f] }
```

**`message_id` is omitted entirely.** A fresh random id per invocation can never match a previous
one, so deduplication never fires while the coordinator's processed-ids Set grows without bound. If
retry idempotency is wanted later, add an explicit `--message-id` flag so the caller controls it.
**`sequence` is likewise omitted** — the coordinator's `check_sequence` returns nil when it is
absent, and a stateless CLI has no way to number monotonically.

Transport, with a read timeout so a wedged coordinator cannot block Claude forever:

```ruby
socket_path = options[:socket] || ENV.fetch("WC_STATUS_SOCKET", "/tmp/work-coordinator-status.sock")
READ_TIMEOUT = 5

begin
  sock = UNIXSocket.new(socket_path)
rescue Errno::ENOENT, Errno::ECONNREFUSED => e
  warn "work-coordinator report: cannot reach coordinator at #{socket_path} (#{e.class})"
  exit 1
end

begin
  sock.write("#{JSON.generate(payload)}\n")
  line = sock.wait_readable(READ_TIMEOUT) && sock.gets
ensure
  sock.close
end

unless line
  warn "work-coordinator report: no reply from coordinator within #{READ_TIMEOUT}s"
  exit 1
end

reply = begin
  JSON.parse(line)
rescue JSON::ParserError
  warn "work-coordinator report: malformed reply: #{line.strip}"
  exit 1
end
```

Exit codes — distinct codes let Claude branch on the outcome without parsing stderr:

| Code | Condition |
|------|-----------|
| 0 | `{"ok":true}` |
| 1 | Socket missing/refused, timeout, malformed reply, usage error, unrecognized `error` |
| 2 | `error: "unknown_work_item"` (`action: give_up`) |
| 3 | `error: "terminal_state"` (`action: abort_pipeline`) |
| 4 | `error: "out_of_sequence"` (`action: drop`) |

```ruby
exit 0 if reply["ok"]

warn "work-coordinator report: #{reply['error']} (action: #{reply['action']})"
exit({ "give_up" => 2, "abort_pipeline" => 3, "drop" => 4 }.fetch(reply["action"], 1))
```

`bin/work-coordinator` already requires the library; confirm `json` and `socket` are reachable and
add `require`s at the top of the branch if not.

**Also create `docs/commands/report.md`** — or run the `docs` skill after the branch is written.
Add `report` to any command index the docs carry.

---

### 6. `InformHuman` use case (new)

**File:** `lib/work_coordinator/application/inform_human.rb`

The counterpart to `NotifyHuman`: it announces without asking. `NotifyHuman` moves the item to
`waiting_for_human` and appends `Reply: <ref> <your response>`; that is right for a question and
wrong for a progress ping, a phase transition, or a crash report.

```ruby
# frozen_string_literal: true

module WorkCoordinator
  module Application
    # Tells the human something about a work item without asking them for
    # anything. Unlike {NotifyHuman} it sends no reply hint and makes no state
    # transition — the agent is still in charge of the item.
    class InformHuman
      # @param message_sender [Ports::MessageSender]
      # @param event_store [#append]
      def initialize(message_sender:, event_store:)
        @message_sender = message_sender
        @event_store = event_store
      end

      # @param work_item_id [String]
      # @param body [String]
      # @param work_item [Domain::WorkItem] the item, already in hand from the caller
      # @return [Domain::WorkItem] unchanged
      def call(work_item_id:, body:, work_item:)
        ref = work_item.external_reference
        @message_sender.send_message(to: nil, body: "[#{ref}] #{body}")
        @event_store.append(
          type: "system.informed",
          work_item_id: work_item_id,
          source: "system",
          data: { ref: ref, body: body }
        )
        work_item
      end
    end
  end
end
```

`work_item:` is passed in rather than looked up: `WorkspaceStatusReceiver#dispatch` already holds it,
and a second repo round-trip per status ping buys nothing.

Add the `require` alongside the other application requires in `lib/work_coordinator.rb`.

---

### 7. WorkspaceStatusReceiver: human notifications

**File:** `lib/work_coordinator/adapters/workspace_status_receiver.rb`

**Constructor** (line 26) — add `inform_human:` as a required keyword next to `notify_human:`, set
`@inform_human`, and document it: `@param inform_human [#call] call(work_item_id:, body:, work_item:)`.

Keep `notify_human:` even though no handler uses it after this change — `WorkspaceStatusReceiver` is
the receiver for agent telemetry generally, and a future type that genuinely asks the human a
question will want it. If the implementer finds an unused-argument lint failure, drop it and note the
removal in the commit body rather than silencing the linter.

**`handle_status_update`** (line 163):

```ruby
def handle_status_update(message, work_item)
  append(work_item, "agent.status_update", message, message: message["message"])
  @inform_human.call(work_item_id: work_item.id, body: message["message"], work_item: work_item)
end
```

**`handle_phase_change`** (line 167):

```ruby
def handle_phase_change(message, work_item)
  @work_item_repo.save(work_item.with(phase: message["phase"], updated_at: Time.now))
  append(work_item, "agent.phase_changed", message, phase: message["phase"])
  @inform_human.call(work_item_id: work_item.id, body: "phase: #{message['phase']}", work_item: work_item)
end
```

Note `work_item` passed to `inform_human` is the pre-save value; only `phase` and `updated_at`
changed and `InformHuman` reads neither, so this is correct. It reads `external_reference`.

**`error`** (line 158) — switch from `notify_human` to `inform_human`:

```ruby
when "error"
  @inform_human.call(work_item_id: work_item.id, body: message["message"], work_item: work_item)
```

An agent error report is not a question. `NotifyHuman` parks the item as `waiting_for_human`, which
invites a human reply that `RouteMessage` will try to `inject` into a pipeline that has already
stopped — the steer fails, and the item stays stuck waiting. Announcing the error and leaving the
state alone is both more honest and recoverable: the human can act through the normal commands.

**`handle_pipeline_advanced` and `task_complete` are unchanged.** `pipeline_advanced` is internal
pane movement with no actionable content; `CompleteWorkItem` already sends `[ref] Done — <summary>`.

**Known limitation, worth a note in the commit body but not worth solving now:** a chatty Claude can
flood the human's iMessage thread with `status_update` pings. There is no rate limiting in this
change. The operator's template is the current throttle — it tells Claude to report "at meaningful
milestones". If flooding shows up in practice, the right fix is a debounce in `InformHuman` keyed on
work item id, not a change to the receiver.

---

### 8. Update `docs/workspace-agent-protocol.md`

Corrections against the sections written for the earlier design:

1. **"Default template" section (line ~237).** Replace the `none` code block. The template has no
   default; when `status_reporting_template` is unset the `reporting_instructions` field is **omitted
   from the payload entirely** rather than sent empty.
2. **Substitution variable table (line ~229).** Add `%{workspace}` (the workspace name, so the
   rendered command line can pass `--workspace`) and `%{task_complete_line}` (a pre-rendered
   `task_complete` invocation, empty for pipeline workspaces). Note `%{cli_command}` now comes from
   the `status_reporting_cli` config key, default `work-coordinator`.
3. **Add a `task_complete` warning.** For a workspace whose registration carries a `pipeline`, the
   template must not advertise `task_complete`: Claude reporting it completes the item early, and the
   agent's own sentinel-driven `task_complete` then fails with `terminal_state`/`abort_pipeline`,
   tearing down a live pipeline. The coordinator enforces this by rendering `%{task_complete_line}`
   as an empty string for pipeline workspaces — an operator who hardcodes the line into their
   template instead of using the variable defeats the guard.
4. **Multi-stage pipelines — stage 1 only, by design.** `reporting_instructions` reaches the pane via
   `handle_command`, which fires when the task first lands. Stages 2..N receive only
   `handoff_instructions` and never see it. This is deliberate: later stages are covered by the
   agent's own `phase_change` and `pipeline_advanced` telemetry, which the coordinator receives
   without Claude's help. Carrying the instructions to every stage would mean persisting them on the
   pipeline state entry and appending them in `advance_state` — a new field and more per-stage text,
   for visibility already covered. Add this as an explicit paragraph so the omission reads as a
   decision rather than an oversight.
5. **`message_id` and `sequence` in CLI reports (line ~300).** Correct the claim that `message_id` is
   "a fresh random identifier". Both fields are omitted. Explain why: a random per-invocation id can
   never dedup and grows the coordinator's processed-ids set unboundedly; a stateless CLI cannot
   number monotonically, and `check_sequence` returns nil when `sequence` is absent, so omission is
   safe.
6. **Exit codes table (line ~310).** Replace the two-row table with the five-row table from change 5.
7. **Human notification table (line ~344).** `error` now reads: notified via `InformHuman`, **no**
   state change, message `[WC-42] <message>`. Rewrite the following `**error**` paragraph to match,
   and update the `InformHuman` section (line ~365) to show the real signature —
   `call(work_item_id:, body:, work_item:)` — and to say the `error` handler uses it too.
8. **Instruction separator.** The agent joins body and instructions with `\n\n`; the labeled
   `--- Status reporting ---` header lives in the operator's template, not in the join logic. State
   this so nobody adds a second separator on the agent side.

---

## Testing

Every spec below must run without a live tmux session, a real coordinator, or the Messages database.

**New spec files:**

- `spec/work_coordinator/application/inform_human_spec.rb` — with `FakeMessageSender` and a fake
  event store: sends `[ref] body` with no reply hint; appends exactly one `system.informed` event
  with `{ref:, body:}`; returns the work item unchanged; makes no repo call (construct it without a
  repo — it takes none).

**Modified spec files:**

- `spec/work_coordinator/config_spec.rb` — `status_reporting_template` is nil when the key is absent
  and returns the string when present; `status_reporting_cli` defaults to `"work-coordinator"` and is
  overridable; `default_content` parses as YAML and leaves both keys commented out (so a fresh
  install stays opt-in).
- `spec/work_coordinator/adapters/workspace_agent_session_spec.rb` — the bulk of the coverage, using
  `FakeWorkspaceAgent` to capture the delivered JSON:
  - no config, or config with no template → payload has no `reporting_instructions` key at all
    (assert `key?`, not the value — a nil value would still serialize)
  - template set, registration with `pipeline: nil` → field present, substitutions correct for all
    five variables, and the `task_complete` line **is** included
  - template set, registration with `pipeline: "build"` → field present and `task_complete` **absent**
  - template referencing an unknown `%{nope}` → field omitted, warning logged, delivery still succeeds
  - a template that is whitespace only → field omitted
  - `inject` never carries `reporting_instructions`, template configured or not
  - unregistered workspace → tmux fallback, unaffected
- `spec/work_coordinator/adapters/workspace_status_receiver_spec.rb` — with a fake `inform_human`
  recording its calls:
  - `status_update` appends the event **and** informs with the verbatim message
  - `phase_change` saves the phase, appends the event, and informs with `"phase: <phase>"`
  - `error` informs and does **not** call `notify_human`, and leaves the work item's state untouched
  - `pipeline_advanced` and `task_complete` inform nobody directly (regression guard)
- `spec/work_coordinator/container_spec.rb` — the container builds an `inform_human` and the status
  receiver holds it; the agent session receives the container's resolved `status_socket_path`.

**`report` command.** Cover it end-to-end against a real `UNIXServer` in the spec (the same shape as
`FakeWorkspaceAgent`, which is the model to copy) rather than mocking sockets: spawn the binary with
`--socket` pointed at the test server and assert on the JSON received and the process exit status.
Cases: happy path exits 0; each error/action pair maps to 2/3/4; a server that accepts and never
replies exits 1 within the timeout; a missing socket path exits 1; a missing required type flag exits
1 without opening a socket. If spawning the binary proves too slow for the suite, extract the payload
construction and reply-to-exit-code mapping into small testable methods and integration-test only the
happy path.

Run `bundle exec rspec` and `bundle exec rubocop` before committing. All green, no exceptions.

---

## Migration and rollout notes

**Existing deployments are unaffected.** With no `status_reporting_template` in `config.yml` — which
is every deployment until an operator opts in — `render_reporting_instructions` returns nil and the
`command` payload is byte-identical to today's.

**Older workspace agents** receive the `reporting_instructions` field and ignore it, as JSON parsers
ignore unknown keys. Claude simply never sees the instructions; nothing breaks. No version
negotiation is needed in either direction.

**Older coordinators** paired with an updated agent send no `reporting_instructions`; the agent's
append is a no-op and the body goes through unchanged.

**The one visible behavior change for existing users is `error`.** An agent error no longer parks the
work item in `waiting_for_human`. Anyone whose workflow depended on finding errored items in the
waiting list will now find them in whatever state they were in. Call this out in the release notes.

**The status socket only exists while `run` is up.** A pane that invokes `report` outside a running
coordinator gets `ENOENT` or `ECONNREFUSED` and exits 1 with a readable message. That is the intended
behavior — but it means the rendered instructions should not promise Claude that reporting always
works, and Claude should not treat a failed report as a reason to abandon its task. Worth a sentence
in the example template.

**Rollout order,** if the coordinator and the workspace agent ship separately: coordinator first. It
sends a field the agent ignores until the agent is updated, which is harmless. The reverse order is
equally harmless but delivers nothing until the coordinator catches up.
