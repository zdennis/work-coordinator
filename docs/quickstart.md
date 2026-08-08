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
  --ref   GE-123 \
  --repo  billing-service \
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
bundle exec ruby bin/work-coordinator send "GE-123 yes, update the fixture and rerun the suite"
```

```
Sent: GE-123 yes, update the fixture and rerun the suite
```

**REF prefix format:** `<REF> <message body>` — the REF must match exactly (case-sensitive) and be separated from the body by a single space. The coordinator parses the leading token as a REF, looks up the matching work item, and routes the message body to its registered tmux pane.

Check status after sending:

```
bundle exec ruby bin/work-coordinator status
```

```
ID                                    REF    STATE   PHASE  TITLE
71380947-2ce7-4799-adbf-be9516583b45  GE-123 active         Fix Kafka abandonment fixture
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

| Variable       | Default                        | Purpose                                          |
|----------------|--------------------------------|--------------------------------------------------|
| `WC_DATABASE`  | `db/work_coordinator.sqlite3`  | Path to the SQLite database file                 |
| `WC_SOCKET`    | `/tmp/work-coordinator.sock`   | Path to the Unix domain socket (local mode)      |
| `WC_RECIPIENT` | _(required for messages mode)_ | Phone number or email for outbound notifications |

---

## What is not yet wired

- **`work-coordinator start`** — there is no CLI command for tmux session tracking; use `register --tmux` directly (as shown above).

---

## Messages.app Mode

In Messages mode the coordinator sends notifications to your iPhone via iMessage
and reads replies by polling `~/Library/Messages/chat.db`.

### Prerequisites

1. Grant Full Disk Access to your terminal app (iTerm2 or Terminal.app):
   System Settings > Privacy & Security > Full Disk Access → add your terminal
2. Configure send-message with your phone number:
   ```
   $ send-message --init
   ```
3. Export your recipient number:
   ```
   $ export WC_RECIPIENT=+1XXXXXXXXXX
   ```

### The `ai:` prefix convention

All replies from your phone must start with `ai: ` (lowercase, followed by a space).
This filters out unrelated messages in the same thread.
The prefix is stripped before routing — the agent receives only the body.

Format: `ai: <REF> <message>`
Example: `ai: GE-123 yes, update the fixture and rerun the suite`

### Step 1 — Register a work item (same as local mode)

```
$ bundle exec ruby bin/work-coordinator register \
    --title "Fix Kafka abandonment fixture" \
    --kind jira \
    --ref GE-123 \
    --repo billing-service \
    --tmux my-project:claude.0
```

### Step 2 — Start the coordinator in messages mode (Terminal 1)

```
$ WC_RECIPIENT=+1XXXXXXXXXX bundle exec ruby bin/work-coordinator run --mode messages
work-coordinator running in messages mode (polling ~/Library/Messages/chat.db)
Listening for messages starting with: ai:
Press Ctrl-C to stop.
```

### Step 3 — Send a notification to your phone (Terminal 2)

```
$ bundle exec ruby bin/work-coordinator notify <work-item-id> "Should I update the Kafka fixture?"
Notification sent.
```

Your phone receives:
```
[GE-123] Should I update the Kafka fixture?
Reply: ai: GE-123 <your response>
```

### Step 4 — Reply from your iPhone

In the Messages conversation, reply:
```
ai: GE-123 yes, update the fixture and rerun the suite
```

Within 5 seconds the coordinator terminal shows:
```
Routed to <id>: yes, update the fixture and rerun the suite
```

And the text arrives in your registered tmux pane (`my-project:claude.0`).

### Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `Errno::EPERM` or `unable to open database file` on chat.db | Full Disk Access not granted to your terminal | System Settings → Privacy & Security → Full Disk Access → add iTerm2 or Terminal.app, then **quit and relaunch** the terminal (and kill/restart tmux if applicable) |
| FDA granted but still denied | tmux server predates the FDA grant | `tmux kill-server`, relaunch terminal, start a new tmux session |
| Verify FDA is working | — | Run `cp ~/Library/Messages/chat.db /tmp/test.db && echo OK && rm /tmp/test.db` — if this prints `OK` the poller will work |
| Reply not picked up | Missing `ai: ` prefix | Start message with exactly `ai: ` (lowercase, space after colon) |
| `send-message` fails | Not configured | Run `send-message --init` |
| Message routed but not delivered to pane | Wrong tmux target | Check `work-coordinator status` and verify --tmux value matches your session |
