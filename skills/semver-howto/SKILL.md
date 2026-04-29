---
name: semver-howto
description: Collision-aware SemVer tag resolver. Default run is dry-run — proposes tags. Use --tag or --release with a specific version to act. --promote and --release require explicit user request.
type: skill
---

# semver-howto

Run [`scripts/resolve-version.sh`](scripts/resolve-version.sh). Default is
dry-run — proposes tags on stdout, no side effects. Use `--help` for all flags.

```sh
resolve-version.sh                          # propose next -rc[n] per module
resolve-version.sh --tag <version>          # create and push a specific RC
resolve-version.sh --release <version>      # create and push a specific clean tag
resolve-version.sh --promote                # promote highest RC to clean release
resolve-version.sh --minor                  # force minor bump in proposals
resolve-version.sh --patch                  # force patch bump in proposals
```

## Workflow

1. Run the script with no action flags → read proposed tags from stdout.
2. Read the diff for each proposed module. Decide the correct bump level
   yourself — the script guesses from commit messages but you judge from
   the actual code:
   - **minor**: new public API, new feature, new parameter, new behavior
   - **patch**: bug fix, internal refactor, dependency update
   - **skip**: README, comments, CI config, non-functional files
   Files that change runtime behavior or user-facing contracts (including
   skill instructions, config schemas, CLI flags) are functional, not docs.
3. For each approved proposal, call back with `--tag <version>` or
   `--release <version>`. Adjust the version if your evaluation differs
   from the script's proposal.

## Constraints

- `--tag` only accepts RC versions (`-rc[n]`). Safe for agents and CI.
- `--release` and `--promote` create clean tags. Only use when the user
  explicitly asks (e.g. "release", "skip RC", "promote").