# work-coordinator

Route messages to AI agents running in tmux panes.

## Overview

When you run AI coding agents in tmux panes, each one eventually stops and waits on you. Answering means finding the right pane, remembering which task it belongs to, and typing into it. work-coordinator removes that step: work items are registered with an external reference (a Jira ticket, an issue number), and any message prefixed with that reference is routed to the pane where the agent is waiting.

Messages arrive through two channels. **Local socket mode** listens on a Unix domain socket, so `work-coordinator send 'MS-123 go ahead'` from any terminal lands in the right pane. **Messages.app mode** polls `~/Library/Messages/chat.db` on macOS, so an agent can text you a question and you can answer from your iPhone. Both run at once by default.

State lives in SQLite. A work item tracks a UUID, title, kind, external reference, repository, and tmux target, and moves from `created` to `active` as messages route to it.

## Prerequisites

- Ruby >= 3.2 and Bundler (`gem install bundler`)
- tmux
- macOS with Messages.app configured, for messages mode only

## Installation

```bash
git clone <repo-url> work-coordinator
cd work-coordinator
bin/setup
```

`bin/setup` installs Homebrew dependencies, the pinned Ruby version via rbenv, and gems. If you manage Ruby yourself, `bundle install` is enough.

## Quick start

Local socket mode, four steps.

**1. Create a tmux session for the agent.**

```bash
tmux new-session -d -s my-project -n claude
```

The `-n claude` flag names the window, making the pane addressable as `my-project:claude.0` (`session:window.pane`).

**2. Register a work item.**

```bash
bundle exec ruby bin/work-coordinator register \
  --title "Fix Kafka abandonment fixture" \
  --kind  jira \
  --ref   MS-123 \
  --repo  acme-billing \
  --tmux  my-project:claude.0
```

```
id:    71380947-2ce7-4799-adbf-be9516583b45
state: created
```

Migrations run automatically on first invocation.

**3. Start the coordinator, in its own terminal.**

```bash
bundle exec ruby bin/work-coordinator run --mode local
```

```
work-coordinator running on /tmp/work-coordinator.sock (local socket)
Press Ctrl-C to stop.
```

**4. Route a message from another terminal.**

```bash
bundle exec ruby bin/work-coordinator send "MS-123 yes, update the fixture and rerun the suite"
```

The message format is `<REF> <body>`. The REF must match the registered reference exactly (case-sensitive) and be separated from the body by a single space. The coordinator strips the REF and delivers only the body to the pane.

Check where things stand with `work-coordinator status`.

## Commands

| Command | Description |
|---------|-------------|
| [`register`](docs/commands/register.md) | Create a work item and print its UUID |
| `start <uuid>` | Transition a work item to `active` |
| `status` | List all work items with state, phase, and title |
| [`run`](docs/commands/run.md) | Start the daemon and listen for inbound messages |
| `send "REF body"` | Send a message to the running daemon over its socket |
| `notify <uuid> "body"` | Send a human notification for a work item |

Run `work-coordinator <command> --help` for command-specific options.

## Modes

`run` enables all modes by default. Restrict with `--mode` (repeatable, comma-separated).

| Mode | Behavior |
|------|----------|
| `all` | Every known mode; currently equivalent to `local,messages`. The default. |
| `local` | Opens a Unix socket at `WC_SOCKET` and listens for `work-coordinator send`. |
| `messages` | Polls `~/Library/Messages/chat.db` for iMessages prefixed with `ai: `. Requires `WC_RECIPIENT`. |

```bash
work-coordinator run --mode local
work-coordinator run -m local,messages
WC_RECIPIENT=+1XXXXXXXXXX work-coordinator run --mode messages
```

Messages mode requires two things beyond the recipient. Your terminal app needs Full Disk Access (System Settings → Privacy & Security → Full Disk Access) — grant it, then quit and relaunch the terminal, and run `tmux kill-server` if a tmux server was already running, since permissions are inherited at launch. And every reply from your phone must begin with `ai: `, which filters out unrelated messages in the thread:

```
ai: MS-123 yes, update the fixture and rerun the suite
```

See [docs/quickstart.md](docs/quickstart.md) for the full messages-mode walkthrough and troubleshooting table.

## Environment variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path used in local mode |
| `WC_RECIPIENT` | _(required for messages mode)_ | Phone number or email for outbound notifications |

## Development

```bash
bundle exec rspec        # test suite
bundle exec rubocop      # lint
```

`script/dev/verify/` holds standalone scenario exercisers that run against fake adapters, so they need no tmux session, socket, or Messages.app:

```bash
ruby script/dev/verify/loopback_e2e.rb
```

See [script/dev/verify/README.md](script/dev/verify/README.md) for conventions.

## Contributing

1. Fork the repository and branch from `main`.
2. Make your change, with tests.
3. Ensure `bundle exec rspec` and `bundle exec rubocop` both pass.
4. Write commit messages in [Conventional Commits](https://www.conventionalcommits.org/) form (`feat:`, `fix:`, `docs:`, `refactor:`).
5. Open a pull request describing what changed and why.

## License

MIT. A `LICENSE` file has not been added to the repository yet.
