---
name: docs
description: Create and update command documentation in docs/commands/ from the CLI definitions in bin/work-coordinator
argument-hint: [create|update] [command-name]
---

# Docs Skill

Keep `docs/commands/` in sync with the CLI defined in `bin/work-coordinator`.

## Usage

```
/docs create [command-name]
/docs update [command-name]
```

If `command-name` is omitted, operate on every command.

## Command discovery

All commands are defined in `bin/work-coordinator`:

1. Read the `COMMANDS` hash near the top — keys are command names, values are the one-line descriptions shown in global help.
2. Read the matching `when "<name>"` branch in the `case command` block. Its `OptionParser` gives you the banner (usage line), the prose description in the `opts.separator` calls, the `Examples:` block, and every `opts.on` flag with its description.
3. Note the argument validation right after `parse!` — required positional arguments and the exact `warn` text on failure.
4. Read the use case the branch calls in `lib/work_coordinator/application/` for real behavior, side effects, and failure modes. The help text says what the flags are; the use case says what actually happens.
5. Check `lib/work_coordinator/container.rb` for which adapters the command's modes select, and note any relevant environment variables (`WC_DATABASE`, `WC_SOCKET`).

The `COMMANDS` hash is the authoritative list. A command in the hash without a `when` branch, or a `when` branch missing from the hash, is a bug worth reporting to the user.

## Template — docs/commands/\<name\>.md

```markdown
# <name>

<1-2 sentence description of what the command does and what it returns>

\`\`\`
work-coordinator <name> [flags] [args]
\`\`\`

<A short paragraph on what happens and what does not happen, plus what to run next.>

## Arguments

<Only if the command takes positional arguments.>

| Argument | Description |
|----------|-------------|
| `<arg>` | What it is |

## Required flags

<Omit this section if there are none.>

| Flag | Description |
|------|-------------|
| `--flag VALUE` | What it does |

## Optional flags

<Omit this section if there are none.>

| Flag | Description |
|------|-------------|
| `--flag VALUE` | What it does, and what happens when omitted |

## Output

<What the command prints on success, as a fenced block, plus the exit code on failure.>

## Environment

<Only if the command reads environment variables.>

| Variable | Default | Purpose |
|----------|---------|---------|
| `WC_SOCKET` | `/tmp/work-coordinator.sock` | Unix socket path |

## Examples

<Practical examples in fenced bash blocks, each with a one-line lead-in.>

## Gotchas

<Failure modes a user would hit, in bold-lead paragraphs. Omit if there are genuinely none.>
```

Omit any section that does not apply. Do not pad a section to fill the template.

## Instructions

### When running `create`

1. Find every command in the `COMMANDS` hash
2. Identify which lack a `docs/commands/<name>.md`
3. For each missing one, gather the details per **Command discovery** above and write the file using the template
4. Add the command to the commands table in `README.md` if that table exists

### When running `update`

1. For each command in scope:
   - Read the current `docs/commands/<name>.md`
   - Re-read the `when` branch and the use case it calls
   - Update the doc wherever it has drifted — new or removed flags, changed defaults, changed output, changed error text
2. Create docs for commands that have none
3. Delete docs for commands no longer in `COMMANDS`, and tell the user which you removed
4. Sync the commands table in `README.md`
5. If a specific command was named, process only that one

## Notes

- Filenames match command names exactly: `docs/commands/run.md`, `docs/commands/register.md`
- Use `docs/commands/register.md` as the reference for tone and depth
- Document real behavior, not just flag names — the value of these docs is in the Gotchas and the Output sections
- Verify examples are runnable before writing them down
- `docs/quickstart.md` covers the end-to-end flow; keep command docs focused on one command and link to the quickstart rather than duplicating it
