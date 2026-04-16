---
name: semver-howto
description: Autonomous, collision-aware Git SemVer tag resolver. Infers the impact zone of the current change, picks minor-vs-patch from commit intent, walks past taken addresses (base or RC) locally and on the remote, and proposes the next free `-rc[n]`. Clean release tags are reserved for manual human promotion.
type: skill
---

# semver-howto

All logic lives in [`scripts/resolve-version.sh`](scripts/resolve-version.sh).
This file tells the agent **when** to call it and **what the rules are**.
It does not re-derive the procedure — read the script's `--help` for flags
and its inline comments for the algorithm.

## When to invoke

- After a code change, when a version tag needs proposing.
- When the user says "tag this" / "bump version" / "what version?".
- From a CI step that delegates tag selection to an agent.

Do **not** invoke for commit-message authoring or changelog generation.

## Rules the script enforces

1. **Impact Zone**: modified paths → `git log -1 -- <paths>` → `git describe
   --match "*v*" <commit>`. Never widens to all tags on a monorepo.
2. **Bump**: `feat:` in impact-zone commits → minor; else patch. Major is
   never autonomous. Override with `--minor` or `--patch` when the agent
   evaluates that commit messages don't reflect the true scope of changes.
3. **Collision**: pattern-scoped `git tag -l` locally, then targeted
   `git ls-remote --tags origin "refs/tags/<candidate>"` for shallow
   pre-flight. Walks forward through taken addresses.
4. **RC-only**: autonomous output is always `-rc[n]`. Clean tags are refused.
5. **`--tag` creates and pushes RC tags**: safe for CI and agents. Only
   applies to `-rc[n]` tags — the script will never create a clean tag.
6. **HITL on `--promote`**: outputs a clean tag proposal and the exact
   `git tag` + `git push` commands. The agent MUST present this to the
   human and wait for explicit approval. Agents are **never authorized**
   to create or push clean release tags autonomously.

## Usage

```sh
./skills/semver-howto/scripts/resolve-version.sh              # propose next -rc[n]
./skills/semver-howto/scripts/resolve-version.sh --tag        # resolve, tag, and push RC
./skills/semver-howto/scripts/resolve-version.sh --promote    # propose clean tag (HITL)
./skills/semver-howto/scripts/resolve-version.sh --paths "a b" # explicit impact zone
./skills/semver-howto/scripts/resolve-version.sh --help       # flags + algorithm notes
```

Exit `0` on success. Non-zero on ambiguous/unsafe state (details on stderr).

## Performance & Safety

- `git describe --match "<prefix>*v*" <commit>` bounds the tag walk to
  relevant refs — critical on monorepos with thousands of per-module tags.
- `git tag -l "<pattern>"` is served from packed-refs; O(matches), not
  O(history).
- `git ls-remote --tags origin "refs/tags/<candidate>"` asks for a single
  ref. No object fetch, no `FETCH_HEAD` churn, typically sub-second even
  against huge remotes. Avoids `git fetch --tags` entirely.
- Diff and log queries are scoped to impact-zone paths, so each run touches
  only the relevant slice of history.
- Safety: RC-only writes, dual local+remote collision check, no push, no
  major bumps, deterministic bootstrap (`v0.1.0-rc1`) when no prior tag
  exists — surfaced on stderr for human confirmation.