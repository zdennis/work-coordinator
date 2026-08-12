# project

Manages DB-backed project records that group work items and map to tmux workspace sessions. Projects support workspace routing in `ai:` iMessage commands and the `--project` flag on `register`.

```
work-coordinator project add NAME [--alias ALIAS] [--workspace NAME]
work-coordinator project list
work-coordinator project set-default NAME_OR_ALIAS
```

Unlike the `alias` command, which stores short-name mappings in `~/.config/work-coordinator/config.yml`, projects live in the SQLite database and carry workspace metadata. When routing an `ai:` message, the router checks DB projects first and falls back to config aliases only when no DB project matches.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `add NAME` | Add a new project |
| `list` | List all projects with their aliases, workspaces, and default flag |
| `set-default NAME_OR_ALIAS` | Set the default project for `ai: status` and project-scoped queries |

## Flags for `add`

### Required

| Argument | Description |
|----------|-------------|
| `NAME` | Project name, e.g. `my-service`. This is the display name stored in the DB — it does not have to match a tmux session name, but `--workspace` must if you want routing to work. |

### Optional

| Flag | Description |
|------|-------------|
| `--alias ALIAS` | Short alias for routing, e.g. `GE`. Used in `ai:` iMessages and `--project` on `register`. |
| `--workspace NAME` | tmux session name this project routes to. Without it, the project is created but `ai:` dispatch cannot deliver messages to any workspace. |

## Output

Adding a project with an alias:

```
Added project: my-service (GE)
```

Adding a project without an alias:

```
Added project: my-service
```

Listing projects:

```
ALIAS       NAME                  WORKSPACE             
------------------------------------------------------------
GE          my-service         my-service         [default]
BI          billing               billing               
```

When no projects exist:

```
No projects.
```

Setting the default project:

```
Default project set to GE (my-service)
```

When the query matches nothing:

```
No project found matching: XYZ
```

When the query is ambiguous (multiple fuzzy matches):

```
Ambiguous: matched GE, GE2. Be more specific.
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_DATABASE` | `db/work_coordinator.sqlite3` | Path to the SQLite database |

## Examples

Add a project with a short alias and workspace:

```bash
work-coordinator project add my-service --alias GE --workspace my-service
```

Add a project without an alias (routable only by full name):

```bash
work-coordinator project add billing --workspace billing
```

List all projects:

```bash
work-coordinator project list
```

Set the default project (used by `ai: status` with no filter and by `ai: default`):

```bash
work-coordinator project set-default GE
```

Restore a previous default:

```bash
work-coordinator project set-default my-service
```

## Gotchas

**Duplicate alias raises an error.** If you try to `add` a project whose `--alias` already exists in the DB, the command exits 1:

```
Error: a project with alias 'MS' already exists.
```

Remove the conflicting project or choose a different alias before retrying.

**`--workspace` must match the tmux session name exactly (case-sensitive).** If `--workspace my-service` does not match the live tmux session `my-service` character-for-character, the router fails to deliver and does not report an error. Verify the session name with `tmux ls` before adding the project.

**A project without `--workspace` cannot route messages.** The `ai:` dispatcher resolves a DB project to its `workspace_name`. If that field is empty, resolution falls through to config aliases and the project record is effectively invisible to routing.

**Only one project can be the default at a time.** `set-default` clears the previous default before marking the new one. There is no confirmation prompt and no undo — run `set-default` again with the previous project name to restore it.

**Projects live in the DB, not `config.yml`.** Running `project add` does not write to `~/.config/work-coordinator/config.yml`. The `alias` and `project` commands are separate systems that can coexist. See [alias](alias.md).
