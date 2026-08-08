---
name: release
description: Release work-coordinator by analyzing changes, bumping the version, tagging, and pushing
argument-hint: [patch|minor|major|<version>]
---

# Release work-coordinator

Analyze changes since the last release, suggest a version bump, and release.

## Usage

```
/release
/release patch
/release minor
/release major
/release <version>
```

## Prerequisites

Check all of these before doing anything else. If any fails, tell the user and stop.

1. **On the `main` branch**
2. **No uncommitted changes** to tracked files — untracked files are fine
3. **Tests pass** — run `bundle exec rspec`. Do not release a red suite.
4. **Lint is clean** — run `bundle exec rubocop`

## Version file

The version lives in `lib/work_coordinator/version.rb`:

```ruby
module WorkCoordinator
  VERSION = "0.1.0"
end
```

Change only the version string. Tags use the format `v<version>` (e.g. `v0.2.0`).

## If an argument is provided

Skip change analysis and use the specified bump or explicit version.

1. Read the current version from `lib/work_coordinator/version.rb`
2. Calculate the new version from the bump type, or use the explicit version given
3. **Update documentation** — run the `docs` skill to sync `docs/commands/` with the current CLI. Commit any doc changes separately: `docs: update command documentation`
4. Update the version in `lib/work_coordinator/version.rb`
5. Commit: `chore(release): bump version to <version>`
6. Check whether the tag already exists — if it does, tell the user and stop
7. Create the tag `v<version>`
8. Push the commit: `git push`
9. Push the tag: `git push origin v<version>`

## If no argument is provided

1. Read the current version from `lib/work_coordinator/version.rb`
2. Find the last tag matching `v*`
3. Analyze changes since that tag:
   - `git log <last-tag>..HEAD --oneline`
   - `git diff <last-tag>..HEAD -- lib/ bin/`
   - If no previous tag exists, this is the initial release
4. Suggest a bump using the guidelines below
5. Show the user the current version, a summary of the changes, and your recommendation with reasoning. Let them confirm or choose differently.
6. Follow steps 3-9 from the section above

## Change analysis guidelines

### Patch (x.y.Z) — internal changes

- Bug fixes, refactoring, performance work, code cleanup
- Documentation-only changes
- New adapter internals that do not change behavior

### Minor (x.Y.0) — new features, backward compatible

- New CLI commands added to the `COMMANDS` hash in `bin/work-coordinator`
- New flags or new accepted values for an existing flag (e.g. a new `--mode`)
- New ports, adapters, or use cases that add capability
- New domain concepts

### Major (X.0.0) — breaking changes

- Removed or renamed commands or flags
- Changed default behavior (e.g. what `run` does with no `--mode`)
- Changed output format that scripts parse — `register`'s `id:`/`state:` lines, `status` columns
- Changed exit codes
- Database schema changes requiring a migration users cannot apply automatically
- Renamed or removed port methods

## Error handling

- Not on `main` — tell the user and stop
- Uncommitted tracked changes — tell the user and stop
- Failing tests or lint offenses — report them and stop; do not offer to skip
- Tag already exists — this version has already been released; tell the user and stop

## No previous tag

If this is the first release:

1. Tell the user this is the initial release
2. Skip change analysis — there is nothing to compare against
3. Use the current version as the release version
4. Proceed with the tag creation and push
