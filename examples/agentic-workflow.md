---
on:
  push:
    branches: [main, master]

permissions:
  contents: read
  issues: read

safe-outputs:
  create-issue:
    title-prefix: "[semver] "
    labels: [release]
    close-older-issues: true
---

# Propose SemVer tags on push

When code is pushed to the default branch, run the semver-howto skill to
propose version tags.

## Steps

1. Run `~/.local/share/agent-skills/semver-howto/skills/semver-howto/scripts/resolve-version.sh`
   with no action flags. Capture the proposed tags from stdout.
2. For each proposed tag, review the changed files since the previous version.
   Skip proposals where only non-functional files changed (README, docs,
   comments, CI config).
3. Create an issue listing the approved proposals. Format:

   ```
   ## Proposed tags

   - `v1.2.3-rc1` — patch bump (bug fix in handler)
   - `billing/v0.4.0-rc1` — minor bump (new adapter feature)

   To apply: run `resolve-version.sh --tag <version>` for each.
   ```

   If no proposals are warranted, do not create an issue.
