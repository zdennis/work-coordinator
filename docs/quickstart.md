# Quickstart

## Prerequisites

- Ruby >= 3.2
- Bundler (`gem install bundler`)
- tmux

## Setup

```
$ git clone <repo-url> work-coordinator
$ cd work-coordinator
$ bundle install
```

> **Note:** The `bin/work-coordinator` script requires `lib/` on the load path. All commands below include `-I lib`. The underlying fix is to add `$LOAD_PATH.unshift File.expand_path('../lib', __dir__)` in `bin/work-coordinator`, but until that lands, use the flag.

---

## Quickstart: Local Mode

### 1. Register a work item

```
$ bundle exec ruby -I lib bin/work-coordinator register \
    --title 'Fix Kafka abandonment fixture' \
    --kind jira \
    --ref MS-123 \
    --repo acme-billing \
    --tmux wc-demo:claude.0
```

Flags:
- `--title` — human-readable label
- `--kind` — tracker type (`jira`, etc.)
- `--ref` — external reference; this becomes the routing key for inbound messages
- `--repo` — repository the work item belongs to
- `--tmux` — tmux target (`session:window.pane`) where messages are delivered

Example output (first run triggers migrations):

```
== 20260805000001 CreateWorkItems: migrating ==================================
-- create_table(:work_items, {id: false})
   -> 0.0002s
...
== 20260805000003 CreateResourceLeases: migrated (0.0001s) ====================

id:    1d60b2af-fdb6-421a-96dc-e5e4448142e5
state: created
```

Subsequent runs skip migrations and print just the `id` and `state` lines.

### 2. Check status

```
$ bundle exec ruby -I lib bin/work-coordinator status
```

```
ID                                    REF           STATE                 PHASE                   TITLE
----------------------------------------------------------------------------------------------------
1d60b2af-fdb6-421a-96dc-e5e4448142e5  MS-123        created                                       Fix Kafka abandonment fixture
```

### 3. Start the coordinator run loop

```
$ bundle exec ruby -I lib bin/work-coordinator run
```

```
work-coordinator running on /tmp/work-coordinator.sock
Press Ctrl-C to stop.
```

The run loop opens a Unix domain socket at `/tmp/work-coordinator.sock` and listens for inbound messages. Keep this running in its own terminal (or background it with `&` and tail `/tmp/wc-run.log`).

### 4. Send a message from another terminal

This is the key feature. Open a second terminal and send a message prefixed with the work item's REF:

```
$ bundle exec ruby -I lib bin/work-coordinator send 'MS-123 yes, update the fixture and rerun the suite'
```

```
Sent: MS-123 yes, update the fixture and rerun the suite
```

The `MS-123` prefix is the REF registered in step 1. The coordinator looks up the matching work item and routes the message to the configured tmux pane.

**REF prefix format:** `<REF> <message body>` — the REF must match exactly (case-sensitive) and be separated from the message by a space.

### 5. What arrives in the tmux pane

> **Observed behavior (2026-08-05):** During the E2E run, the message was accepted by the socket but was not relayed to the tmux pane. The work item remained in `created` state after the send. The coordinator appears to require the work item to be in `active` state before routing messages to the configured tmux target. The pane showed only an idle shell prompt.
>
> Until a state-transition mechanism is documented, treat tmux delivery as not yet fully wired for items in `created` state.

---

## How routing works

When a message arrives on the socket, the coordinator parses the leading token as a REF, queries the database for a work item with that external reference, and delivers the message body to the tmux pane recorded on that work item (via `tmux send-keys` or equivalent). If no matching work item is found, or if the item is not in a routable state, the message is dropped.

---

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database file |
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Path to the Unix domain socket |

---

## What is not wired yet

- **Messages.app / iMessage polling** — `chat.db` integration is not implemented. Inbound iMessages are not read or processed.
- **Outbound notifications** — `notify_human` via `AppleScriptMessageSender` is present in the codebase but not connected end-to-end. Outbound Messages.app delivery does not work yet.
- **State transitions** — there is no CLI command to move a work item from `created` to `active`. Message routing to tmux panes appears to depend on the work item being active.
