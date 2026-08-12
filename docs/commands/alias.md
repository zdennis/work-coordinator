# alias

Manages short aliases for workspace project names, so you can type `GE` instead of `my-service`. Aliases are stored in `~/.config/work-coordinator/config.yml` under the `aliases` key; `init` seeds a default `WC -> work-coordinator` alias when it creates a fresh config file.

```
work-coordinator alias
work-coordinator alias list
work-coordinator alias add SHORT PROJECT
work-coordinator alias remove SHORT
```

With no subcommand (or `list`), prints every configured alias. `add` creates or overwrites an alias. `remove` deletes one. `SHORT` is trimmed and upcased before being stored or looked up, so `ge` and `GE` refer to the same alias.

## Arguments

| Argument | Description |
|----------|-------------|
| `SHORT` | Short name for the alias, e.g. `GE`. Normalized to uppercase. |
| `PROJECT` | Workspace project name the alias points to, e.g. `my-service`. |

## Output

Listing aliases:

```
SHORT       PROJECT
WC          work-coordinator
GE          my-service
```

When no aliases are configured:

```
No aliases configured.
```

Adding an alias:

```
Added alias: GE -> my-service
```

Removing an alias:

```
Removed alias: GE
```

Removing an alias that does not exist exits 1:

```
No such alias: GE
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `XDG_CONFIG_HOME` | `~/.config` | Base directory for the config file |

## Examples

List configured aliases:

```bash
work-coordinator alias
```

Add an alias for each of your workspace projects:

```bash
work-coordinator alias add GE my-service
work-coordinator alias add BI billing
```

Remove an alias you no longer need:

```bash
work-coordinator alias remove BI
```

## Relationship to `project`

The `alias` and `project` commands are two separate systems that both resolve short names to workspaces.

| | `alias` | `project` |
|---|---|---|
| Storage | `~/.config/work-coordinator/config.yml` | SQLite database |
| Carries workspace metadata | No — maps SHORT → project name | Yes — stores `workspace_name` and `alias` fields |
| Supports `ai: default` / `ai: status PROJECT` | No | Yes |
| Supports `register --project` | No | Yes |
| Created by | `work-coordinator alias add SHORT NAME` | `work-coordinator project add NAME --alias SHORT` |

When the `ai:` dispatcher resolves a keyword it checks DB projects first (`project_resolver`). If a DB project matches and has a `workspace_name`, that workspace is used. Only when no DB project matches does the dispatcher fall back to config aliases. This means a DB project with the same alias as a config alias will always win.

You can use both systems at once. A common setup is to keep config aliases for quick one-off workspaces and register DB projects for anything that needs `ai: status`, `ai: default`, or `register --project` tagging.

## Gotchas

**`alias add` overwrites silently.** Adding an alias with a short name that already exists replaces its target with no confirmation prompt.

**`SHORT`/`PROJECT` are not validated against real workspace projects.** Nothing checks that `PROJECT` matches an entry in `workspace list` — a typo is stored as-is and only surfaces later when something tries to use it.

**`alias` creates the config file if it does not exist.** Unlike `init`, running `alias add`/`remove` before `init` will create `~/.config/work-coordinator/config.yml` with just the `ai_command` default and your new alias — it does not require running `init` first.

**Comments in `config.yml` are not preserved.** `add`/`remove` rewrite the file from parsed YAML, so any comments you hand-add below the header line will be lost the next time you run `alias add` or `alias remove`.

**Aliases are resolved when dispatching AI commands.** When `work-coordinator run` dispatches an inbound message, the extracted keyword is first checked against configured aliases (case-insensitive) before falling back to fuzzy-matching against `workspace list`. This means `GE` in an instruction routes directly to `my-service` without needing an exact or fuzzy project name match.
