# config

Read or write a single property in the work-coordinator configuration file.

```
work-coordinator config <key> [value]
```

With no arguments, the command prints the path to the config file followed by its full contents. With one argument, it prints the current value of `key` (falling back to its compiled-in default when the key is absent from the file). With two arguments, it writes `value` to the config file and prints the value that was stored. Boolean strings (`true`/`false`) and plain integers are coerced to their native types; everything else is stored as a string.

## Arguments

| Argument | Description |
|----------|-------------|
| `key` | The configuration property to read or write (see supported keys below) |
| `value` | The new value to set. Omit to read the current value. |

## Supported keys

| Key | Default | Description |
|-----|---------|-------------|
| `ai_command` | `claude -p` | Command used to invoke the AI agent |
| `role` | `default` | Active role profile for the coordinator |
| `instruction_context` | _(empty)_ | Extra context injected into agent instructions |
| `slash_commands_enabled` | `true` | Allow slash commands in routed messages |
| `tmux_fallback_enabled` | `true` | Fall back to tmux delivery when a workspace agent's socket is gone |
| `dispatch_via_sockets` | `true` | Steer registered workspace agents via their socket instead of tmux |
| `implicit_reply_enabled` | `true` | Allow bare `reply: …` to route to the single waiting item |
| `auto_launch_workspace` | `false` | Automatically launch dormant workspaces when routing AI commands |
| `workspace_launch_timeout_seconds` | `20` | Max seconds to wait for a launched workspace to become active |

## Output

On a read, the raw value is printed, one line:

```
default
```

On a write, the stored value is echoed back:

```
home
```

Exit code 1 on an unknown key or missing argument.

## Examples

Print the config file path and contents:

```bash
work-coordinator config
```

Read the current role:

```bash
work-coordinator config role
```

Set the role to `home`:

```bash
work-coordinator config role home
```

Disable implicit replies:

```bash
work-coordinator config implicit_reply_enabled false
```

Read the AI command:

```bash
work-coordinator config ai_command
```

## Gotchas

**Unknown keys exit 1.** The command refuses to read or write keys not in its supported list, printing the full list to stderr.

**Values are not validated beyond type coercion.** Setting `workspace_launch_timeout_seconds` to a non-numeric string stores it as a string; the coordinator will fail later when it tries to use that value as an integer.

**Boolean keys store native booleans.** Passing `true` or `false` (case-insensitive) writes a YAML boolean, not the string `"true"`. Reading such a key back prints `true` or `false` without quotes.

**The config file must exist for writes.** If you have not run `work-coordinator init`, the command creates the file automatically via `write_data!`, but any custom comments in an existing file are preserved.
