# workspace

Dispatch a command to a named registered workspace agent through the coordinator.

```
work-coordinator workspace send <name> <body> [--ref REF] [--from NAME]
```

The coordinator looks up `<name>` in its agent registry and writes a `command` JSON message
to that agent's Unix socket. The agent receives it exactly as it would receive a
coordinator-initiated command — no changes to the target agent are required.

The coordinator generates a work item reference if `--ref` is omitted. The reference appears
in the success output and in the forwarded payload, but **no work item is registered** in the
coordinator's database. Status reporting for the dispatched task is handled by the target agent
using its normal `report` channel.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `send` | Dispatch a command to a named registered agent |

## Arguments (send)

| Argument | Description |
|----------|-------------|
| `<name>` | Registered agent name, e.g. `homebrew-bin` |
| `<body>` | Command text to forward to the agent |

## Optional flags (send)

| Flag | Description |
|------|-------------|
| `--ref REF` | Work item reference to use. Coordinator generates one (`WC-d-<hex>`) when omitted. |
| `--from NAME` | Originating agent name, included in the forwarded payload for audit logging. |

## Output

On success:

```
Dispatched to homebrew-bin (ref: WC-d-3a7f1b2e9c4d6f80)
```

On failure, exits 1 with one of:

```
work-coordinator workspace send: agent_not_found (target: homebrew-bin)
work-coordinator workspace send: agent_unreachable (target: homebrew-bin)
work-coordinator workspace send: coordinator not reachable — No such file or directory
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path the coordinator is listening on |

## Examples

Dispatch a command to a registered agent:

```bash
work-coordinator workspace send homebrew-bin 'update the formula to 0.23.0'
```

Supply an explicit work item reference:

```bash
work-coordinator workspace send myapp 'run the integration suite' --ref WC-42
```

Include the originating workspace for audit:

```bash
work-coordinator workspace send myapp 'deploy to staging' --from my-workspace
```

## Gotchas

**The target agent must be registered.** `workspace send` uses the coordinator's agent registry.
If the target has not called `register` (or has called `deregister`), the coordinator returns
`agent_not_found` and exits 1.

**No tmux fallback.** Unlike coordinator-initiated delivery, dispatch does not fall back to
`tmux send-keys` when the agent's socket is gone. A missing or refusing socket returns
`agent_unreachable` immediately.

**The coordinator must be running.** `workspace send` connects to the coordinator's main socket.
If the daemon is not running, the command fails with a connection error.

**No work item is created.** The dispatched ref is included in the forwarded payload for the
agent to use when reporting status, but the coordinator does not register a work item for it.
Queries like `work-coordinator status` will not show it.
