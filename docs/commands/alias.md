# alias

Manages short aliases for workspace project names, so you can type `GE` instead of `growth-engine`. Aliases are stored in `~/.config/work-coordinator/config.yml` under the `aliases` key; `init` seeds a default `WC -> work-coordinator` alias when it creates a fresh config file.

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
| `PROJECT` | Workspace project name the alias points to, e.g. `growth-engine`. |

## Output

Listing aliases:

```
SHORT       PROJECT
WC          work-coordinator
GE          growth-engine
```

When no aliases are configured:

```
No aliases configured.
```

Adding an alias:

```
Added alias: GE -> growth-engine
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
work-coordinator alias add GE growth-engine
work-coordinator alias add BI billing
```

Remove an alias you no longer need:

```bash
work-coordinator alias remove BI
```

## Gotchas

**`alias add` overwrites silently.** Adding an alias with a short name that already exists replaces its target with no confirmation prompt.

**`SHORT`/`PROJECT` are not validated against real workspace projects.** Nothing checks that `PROJECT` matches an entry in `workspace list` — a typo is stored as-is and only surfaces later when something tries to use it.

**`alias` creates the config file if it does not exist.** Unlike `init`, running `alias add`/`remove` before `init` will create `~/.config/work-coordinator/config.yml` with just the `ai_command` default and your new alias — it does not require running `init` first.

**Comments in `config.yml` are not preserved.** `add`/`remove` rewrite the file from parsed YAML, so any comments you hand-add below the header line will be lost the next time you run `alias add` or `alias remove`.

**No consumer yet.** Aliases are stored and listed, but no other command currently resolves a short name into a project when dispatching or registering work items — that wiring is a separate follow-up.
