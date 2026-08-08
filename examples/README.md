# Examples

Runnable walkthroughs of the two work-coordinator workflows. Both scripts use
placeholder values — read them before running, and edit the `# NOTE:` lines to
match your setup.

| Script | What it shows |
|--------|---------------|
| [`local-socket-workflow.sh`](local-socket-workflow.sh) | Register a work item, run the daemon in local socket mode, and route a message to a tmux pane |
| [`messages-mode-workflow.sh`](messages-mode-workflow.sh) | The same flow driven from your iPhone over iMessage |

## Prerequisites

- Ruby >= 3.2 and Bundler, with `bundle install` already run
- tmux
- For messages mode: macOS with Messages.app configured, `send-message --init`
  run once, and Full Disk Access granted to your terminal app

## Running

```bash
./examples/local-socket-workflow.sh
```

Both scripts run from the repository root and invoke the CLI through
`bundle exec ruby bin/work-coordinator`. They write to the SQLite database at
`WC_DATABASE` (default `db/work_coordinator.sqlite3`), so the work items they
register persist after the script exits — check them with
`bundle exec ruby bin/work-coordinator status`.

The local socket script starts and stops the coordinator for you. The messages
script leaves the coordinator running in the foreground, since the interesting
part is replying from your phone; stop it with Ctrl-C.
