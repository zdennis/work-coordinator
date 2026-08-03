# Verify Scripts

Each script in this directory is a standalone executable scenario exerciser that uses fake adapters to test behavior without real infrastructure.

## Usage

Run any script directly with Ruby:

```
ruby script/dev/verify/some_scenario.rb
```

Or execute directly (scripts are chmod +x):

```
./script/dev/verify/some_scenario.rb
```

## Output

Scripts use `term-ansicolor` for colored output:

- **Green** — pass
- **Red** — fail
- **Cyan** — section headers
- **Yellow** — informational messages

## Writing a Verify Script

1. Add a shebang: `#!/usr/bin/env ruby`
2. Require the shared helper: `require_relative "support/output_helpers"`
3. Use `section`, `pass`, `fail`, `info`, and `separator` to structure output
4. Exit with a non-zero status if any checks fail
