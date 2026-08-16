# report

Send a single status report to the running coordinator's status socket and exit.

Intended to be run by an AI agent (e.g. Claude) from inside a workspace pane. The coordinator must be running and listening on its status socket for reports to be accepted.

## Usage

```
work-coordinator report --ref <ref> --type <type> [options]
```

## Types and required flags

| Type | Required flags |
|------|----------------|
| `status_update` | `--message` |
| `phase_change` | `--phase` |
| `pipeline_advanced` | `--from-pane`, `--to-pane` |
| `task_complete` | `--summary` |
| `error` | `--message` |

## Options

| Flag | Required | Default |
|------|----------|---------|
| `--ref REF` | yes | — |
| `--type TYPE` | yes | — |
| `--workspace NAME` | no | `$WC_WORKSPACE` |
| `--message TEXT` | for `status_update`, `error` | — |
| `--phase TEXT` | for `phase_change` | — |
| `--summary TEXT` | for `task_complete` | — |
| `--from-pane N` | for `pipeline_advanced` | — |
| `--to-pane N` | for `pipeline_advanced` | — |
| `--socket PATH` | no | `$WC_STATUS_SOCKET`, else `/tmp/work-coordinator-status.sock` |

## Exit codes

| Code | Condition |
|------|-----------|
| 0 | Report accepted (`{"ok":true}`) |
| 1 | Socket missing/refused, timeout, malformed reply, usage error |
| 2 | `error: "unknown_work_item"` (`action: give_up`) |
| 3 | `error: "terminal_state"` (`action: abort_pipeline`) |
| 4 | `error: "out_of_sequence"` (`action: drop`) |

## Examples

```sh
# Report a progress milestone
work-coordinator report --ref WC-42 --type status_update --message "installing deps"

# Signal a phase transition
work-coordinator report --ref WC-42 --type phase_change --phase implementing

# Report an unrecoverable error
work-coordinator report --ref WC-42 --type error --message "bundle install failed"

# Signal task completion (non-pipeline workspaces only)
work-coordinator report --ref WC-42 --type task_complete --summary "auth refactor done"

# Use a custom socket path
work-coordinator report --ref WC-42 --type status_update --message "tests passing" \
  --socket /var/run/wc-status.sock
```

## Notes

- `message_id` and `sequence` are omitted from CLI reports. A random per-invocation id cannot
  deduplicate and would grow the coordinator's processed-ids set unboundedly; a stateless CLI
  cannot number monotonically, and the coordinator's `check_sequence` returns nil when
  `sequence` is absent.
- The status socket only exists while `work-coordinator run` is up. A failed report (exit 1)
  is not a reason to abandon the task — the coordinator may have restarted or be temporarily
  unavailable.
- For pipeline workspaces, do **not** use `task_complete` unless the operator's template
  explicitly includes it via `%{task_complete_line}`. Reporting it early completes the work
  item before the pipeline's own sentinel fires, causing the subsequent sentinel to fail with
  `terminal_state`/`abort_pipeline`.
