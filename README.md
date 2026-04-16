# semver-howto

Agent-agnostic skill for autonomous, collision-aware SemVer Git tagging.

Resolves the next available `-rc[n]` tag scoped to your change's impact zone,
with local + remote collision checks. Clean releases require human approval.

## Quick install

Auto-detects installed agents (Claude Code, Cursor, Aider, Windsurf):

```sh
curl -sL https://raw.githubusercontent.com/gugabfigueiredo/semver-howto/master/install.sh | bash
```

Or clone and run locally:

```sh
git clone https://github.com/gugabfigueiredo/semver-howto.git
./semver-howto/install.sh
```

### Per-agent install

```sh
./install.sh --agent claude-code              # global — available in all projects
./install.sh --agent claude-code --project .  # project-scoped
./install.sh --agent cursor --project .       # Cursor project rules
./install.sh --agent aider                    # prints config to add manually
./install.sh --agent windsurf --project .     # Windsurf project rules
./install.sh --version v0.2.0                 # pin to a specific release
```

### What the installer does

1. Clones the repo to `~/.local/share/agent-skills/semver-howto/` (or updates it).
2. Creates the appropriate symlink or config for each agent:

| Agent       | Global                                   | Project-scoped                          |
| ----------- | ---------------------------------------- | --------------------------------------- |
| Claude Code | `~/.claude/skills/semver-howto` symlink  | `.claude/skills/semver-howto` symlink   |
| Cursor      | `~/.cursor/rules/semver-howto.mdc`       | `.cursor/rules/semver-howto.mdc`        |
| Aider       | prints `read:` line for `.aider.conf.yml`| same, project-level                     |
| Windsurf    | not supported globally                   | `.windsurf/rules/semver-howto.md` link  |

Update: `git -C ~/.local/share/agent-skills/semver-howto pull`

### GitHub Actions

```yaml
- uses: gugabfigueiredo/semver-howto@master
  id: semver
  with:
    tag: "true"  # creates and pushes the RC tag
# ${{ steps.semver.outputs.version }}
```

## Usage

```sh
./skills/semver-howto/scripts/resolve-version.sh              # propose next -rc[n]
./skills/semver-howto/scripts/resolve-version.sh --tag        # resolve, tag, and push RC
./skills/semver-howto/scripts/resolve-version.sh --minor      # force minor bump
./skills/semver-howto/scripts/resolve-version.sh --patch      # force patch bump
./skills/semver-howto/scripts/resolve-version.sh --promote    # propose clean tag (HITL)
./skills/semver-howto/scripts/resolve-version.sh --help       # all flags
```

## Rules

- **RC-only**: autonomous output is always `-rc[n]`. Clean tags are never created automatically.
- **`--tag`**: creates and pushes RC tags. Safe for CI and agents.
- **`--promote`**: proposes a clean release tag. Human must approve, tag, and push.
- **`--minor` / `--patch`**: override commit-message bump detection when the agent evaluates the true scope.
- **Collision-aware**: walks past taken addresses locally and on the remote via targeted `git ls-remote`.