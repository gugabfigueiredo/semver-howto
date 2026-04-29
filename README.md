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

### Agentic workflows

See [`examples/agentic-workflow.md`](examples/agentic-workflow.md) for a
GitHub agentic workflow template that runs the skill on push and proposes
tags via issue.

## Usage

```sh
./skills/semver-howto/scripts/resolve-version.sh                          # propose next -rc[n] per module
./skills/semver-howto/scripts/resolve-version.sh --tag <version>          # create and push a specific RC
./skills/semver-howto/scripts/resolve-version.sh --release <version>      # create and push a specific clean tag
./skills/semver-howto/scripts/resolve-version.sh --promote                # promote highest RC to clean release
./skills/semver-howto/scripts/resolve-version.sh --minor                  # force minor bump in proposals
./skills/semver-howto/scripts/resolve-version.sh --patch                  # force patch bump in proposals
./skills/semver-howto/scripts/resolve-version.sh --help                   # all flags
```

## Rules

- **Dry-run by default**: proposes tags on stdout, no side effects.
- **`--tag`**: creates and pushes RC tags only. Safe for agents and CI.
- **`--release` / `--promote`**: create clean tags. Only when explicitly requested.
- **`--minor` / `--patch`**: override commit-message bump detection when the agent evaluates the true scope.
- **Collision-aware**: walks past taken addresses locally and on the remote via targeted `git ls-remote`.