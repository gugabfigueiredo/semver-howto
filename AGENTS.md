# AGENTS.md

Agent-agnostic skills published by this repo.

| Skill          | Entry                                     |
| -------------- | ----------------------------------------- |
| `semver-howto` | [`skills/semver-howto/SKILL.md`](skills/semver-howto/SKILL.md) |

## Contract

- Skills are plain Markdown + POSIX Bash. No vendor scaffolding.
- `SKILL.md` = *when/why*. `scripts/` = *how*. Prefer calling the script.
- Mutating skills must: (1) pattern-scoped local check, (2) shallow `ls-remote`
  pre-flight, (3) **propose, not push**, (4) autonomous writes limited to `-rc[n]`.