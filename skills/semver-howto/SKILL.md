---
name: semver-howto
description: Collision-aware SemVer RC tag resolver. Run resolve-version.sh to propose or create the next -rc[n] tag. Clean releases require human approval via --promote.
type: skill
---

# semver-howto

Run [`scripts/resolve-version.sh`](scripts/resolve-version.sh) to resolve the
next available SemVer RC tag. Use `--help` for the full algorithm.

```sh
resolve-version.sh              # propose next -rc[n]
resolve-version.sh --tag        # resolve, create, and push RC
resolve-version.sh --minor      # force minor bump
resolve-version.sh --patch      # force patch bump
resolve-version.sh --promote    # propose clean tag (HITL — see below)
```

## Constraints

- Autonomous output is always `-rc[n]`. The script refuses to create clean tags.
- `--promote` requires **explicit user request** (e.g. "promote", "release",
  "cut a release"). Never run `--promote` on your own initiative.
  When the user asks, run the script — it outputs the proposed clean tag and
  the exact `git tag` + `git push` commands. Execute those commands for the user.