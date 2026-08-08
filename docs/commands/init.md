# init

Creates the default configuration file at `~/.config/work-coordinator/config.yml`.

```
work-coordinator init
```

If the file does not exist, `init` creates the directory and writes the defaults. If the file already exists, it reports that and exits without making any changes — it is safe to run repeatedly.

## Output

When the file is created:

```
Created /Users/<you>/.config/work-coordinator/config.yml
```

When the file already exists:

```
Config file already exists: /Users/<you>/.config/work-coordinator/config.yml
```

## Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `XDG_CONFIG_HOME` | `~/.config` | Base directory for the config file |

## Examples

First-time setup:

```bash
work-coordinator init
```

Then edit the config to change the AI command:

```bash
# ~/.config/work-coordinator/config.yml
ai_command: "claude --dangerously-skip-permissions -p"
```

## Gotchas

**`init` never overwrites an existing config.** If you want to reset to defaults, delete the file first:

```bash
rm ~/.config/work-coordinator/config.yml && work-coordinator init
```

**Auto-init on first use.** If no config file exists when the coordinator starts dispatching AI commands, it runs `init` automatically and prints a notice. You only need to run `init` explicitly if you want to review or customise the defaults before first use.
