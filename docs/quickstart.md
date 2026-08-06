# Quickstart

## Prerequisites

- Ruby >= 3.2, Bundler (`gem install bundler`), tmux

```
git clone <repo-url> work-coordinator
cd work-coordinator
bundle install
```

---

## Quickstart: Local Socket Mode

### Step 1: Create a tmux session for your agent

```
tmux new-session -d -s my-project -n claude
```

The `-n claude` flag names the window `claude`. The `--tmux` flag in the next step references this as `my-project:claude.0` (session:window.pane).

### Step 2: Register a work item

```
bundle exec ruby bin/work-coordinator register \
  --title "Fix Kafka abandonment fixture" \
  --kind  jira \
  --ref   MS-123 \
  --repo  acme-billing \
  --tmux  wc-demo:claude.0
```

Flags:
- `--title` — human-readable label for this work item
- `--kind`  — tracker type (`jira`, etc.)
- `--ref`   — external reference; becomes the routing key for inbound messages
- `--repo`  — repository this work item belongs to
- `--tmux`  — tmux target (`session:window.pane`) where messages are delivered

Output (migrations run on first invocation only):

```
id:    71380947-2ce7-4799-adbf-be9516583b45
state: created
```

### Step 3: Start the coordinator (Terminal 1)

```
bundle exec ruby bin/work-coordinator run
```

```
work-coordinator running on /tmp/work-coordinator.sock
Press Ctrl-C to stop.
```

This opens a Unix domain socket at `/tmp/work-coordinator.sock` and listens for inbound messages. Keep this running while you work.

### Step 4: Route a reply (Terminal 2)

```
bundle exec ruby bin/work-coordinator send "MS-123 yes, update the fixture and rerun the suite"
```

```
Sent: MS-123 yes, update the fixture and rerun the suite
```

**REF prefix format:** `<REF> <message body>` — the REF must match exactly (case-sensitive) and be separated from the body by a single space. The coordinator parses the leading token as a REF, looks up the matching work item, and routes the message body to its registered tmux pane.

Check status after sending:

```
bundle exec ruby bin/work-coordinator status
```

```
ID                                    REF    STATE   PHASE  TITLE
71380947-2ce7-4799-adbf-be9516583b45  MS-123 active         Fix Kafka abandonment fixture
```

The work item transitions from `created` to `active` once a message is routed to it.

### Step 5: What the agent receives

Contents of `wc-demo:claude.0` after the send:

```
yes, update the fixture and rerun the suite
```

The REF prefix is stripped; only the message body is delivered to the pane. In a real Claude Code session this routes into the agent's input. (In the example above the pane was an interactive shell rather than a Claude Code session, which is why the shell tried to execute `yes,` as a command.)

---

## Environment variables

| Variable      | Default                        | Purpose                           |
|---------------|--------------------------------|-----------------------------------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3`  | Path to the SQLite database file  |
| `WC_SOCKET`   | `/tmp/work-coordinator.sock`   | Path to the Unix domain socket    |

---

## What is not yet wired

- **Messages.app / iMessage polling** — `chat.db` integration is not implemented; inbound iMessages are not read or processed.
- **Outbound notifications** — `notify_human` via `AppleScriptMessageSender` is present in the codebase but not connected end-to-end; outbound Messages.app delivery does not work yet.
- **`work-coordinator start`** — there is no CLI command for tmux session tracking; use `register --tmux` directly (as shown above).
