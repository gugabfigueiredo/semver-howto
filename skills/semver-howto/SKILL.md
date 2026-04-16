---
name: semver-howto
description: Collision-aware SemVer tag resolver. Run resolve-version.sh to propose or create version tags. RC tags are the default; clean releases require explicit user request via --release or --promote.
type: skill
---

# semver-howto

Run [`scripts/resolve-version.sh`](scripts/resolve-version.sh) to resolve the
next available SemVer tag. Use `--help` for the full algorithm.

```sh
resolve-version.sh              # propose next -rc[n]
resolve-version.sh --tag        # resolve, create, and push RC
resolve-version.sh --release    # resolve, create, and push clean tag (no RC)
resolve-version.sh --promote    # promote highest RC to clean release
resolve-version.sh --minor      # force minor bump
resolve-version.sh --patch      # force patch bump
```

## Constraints

- Default output is always `-rc[n]`. Use `--tag` to create and push RCs.
- `--release` and `--promote` create clean version tags. Only use these
  when the user explicitly asks (e.g. "release", "skip RC", "promote",
  "cut a release"). Never run these on your own initiative.