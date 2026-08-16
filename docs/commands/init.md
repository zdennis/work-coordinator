# init

Creates or updates the configuration file at `~/.config/work-coordinator/config.yml`.

```
work-coordinator init
```

`init` is safe to run at any time. Its behavior depends on the current state of the config file:

- **File does not exist** — creates the directory and writes a full default config, including the built-in `status_reporting_template`.
- **File exists, `status_reporting_template` key is absent** — adds the default template to the existing config without touching anything else.
- **File exists, `status_reporting_template` is already set** — prompts before overwriting: `status_reporting_template already set. Overwrite? [y/N]`. Enter `y` to replace it with the current default; any other input leaves the file unchanged.

## Output

When the file is created:

```
Created /Users/<you>/.config/work-coordinator/config.yml
```

When the template is added to an existing config:

```
Added default status_reporting_template to /Users/<you>/.config/work-coordinator/config.yml
```

When the template is overwritten after confirmation:

```
Updated status_reporting_template in /Users/<you>/.config/work-coordinator/config.yml
```

When the prompt is declined:

```
No changes made.
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

Update the reporting template on an existing install (will prompt if one exists):

```bash
work-coordinator init
```

Then edit the config to customise it:

```yaml
# ~/.config/work-coordinator/config.yml
ai_command: "claude --dangerously-skip-permissions -p"
slash_commands_enabled: true   # set to false to disable /verb shorthand routing
aliases:
  WC: work-coordinator
```

## Gotchas

**To fully reset to defaults**, delete the file first:

```bash
rm ~/.config/work-coordinator/config.yml && work-coordinator init
```

**Auto-init on first use.** If no config file exists when the coordinator starts dispatching AI commands, it runs `init` automatically and prints a notice. You only need to run `init` explicitly if you want to review or customise the defaults before first use.
