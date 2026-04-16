#!/usr/bin/env bash
# install.sh — install semver-howto skill for local agents
#
# Usage:
#   ./install.sh                        # auto-detect agents, global install
#   ./install.sh --agent claude-code    # specific agent
#   ./install.sh --agent cursor --project .  # project-scoped
#   curl -sL https://raw.githubusercontent.com/gugabfigueiredo/semver-howto/master/install.sh | bash

set -euo pipefail

REPO="https://github.com/gugabfigueiredo/semver-howto.git"
SKILL_NAME="semver-howto"
SKILL_REL="skills/semver-howto"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/agent-skills"
AGENT=""
PROJECT=""
VERSION=""

usage() {
  cat <<'EOF'
install.sh — install semver-howto skill for local agents.

FLAGS
  --agent NAME    Install for a specific agent: claude-code, cursor, aider, windsurf.
                  Default: auto-detect installed agents.
  --project DIR   Install as project-scoped (symlink into project dir).
                  Default: global (user-level) install.
  --version TAG   Pin to a specific git tag/branch (default: master).
  --help          This message.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)   AGENT="$2"; shift 2 ;;
    --project) PROJECT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --help)    usage ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
done

info() { echo "[install] $*"; }
warn() { echo "[install] WARN: $*"; }

# ── clone / update ───────────────────────────────────────────────────
CLONE_DIR="${DATA_DIR}/${SKILL_NAME}"

if [[ -d "$CLONE_DIR/.git" ]]; then
  info "updating ${CLONE_DIR}"
  git -C "$CLONE_DIR" fetch --tags
  git -C "$CLONE_DIR" pull --ff-only 2>/dev/null || true
else
  info "cloning to ${CLONE_DIR}"
  mkdir -p "$DATA_DIR"
  git clone "$REPO" "$CLONE_DIR"
fi

if [[ -n "$VERSION" ]]; then
  info "pinning to ${VERSION}"
  git -C "$CLONE_DIR" checkout "$VERSION"
fi

SKILL_SRC="${CLONE_DIR}/${SKILL_REL}"

# ── agent wiring ─────────────────────────────────────────────────────
link_skill() {
  local target="$1" name="$2"
  mkdir -p "$(dirname "$target")"
  if [[ -L "$target" ]]; then
    rm "$target"
  elif [[ -e "$target" ]]; then
    warn "${target} exists and is not a symlink — skipping"
    return
  fi
  ln -s "$SKILL_SRC" "$target"
  info "${name}: linked ${target} → ${SKILL_SRC}"
}

install_claude_code() {
  if [[ -n "$PROJECT" ]]; then
    link_skill "${PROJECT}/.claude/skills/${SKILL_NAME}" "claude-code (project)"
  else
    link_skill "$HOME/.claude/skills/${SKILL_NAME}" "claude-code (global)"
  fi
}

install_cursor() {
  if [[ -n "$PROJECT" ]]; then
    local rules_dir="${PROJECT}/.cursor/rules"
    mkdir -p "$rules_dir"
    if [[ ! -f "${rules_dir}/${SKILL_NAME}.mdc" ]]; then
      cat > "${rules_dir}/${SKILL_NAME}.mdc" <<MDC
---
description: Autonomous collision-aware SemVer tag resolver
globs:
alwaysApply: false
---
@file ${SKILL_SRC}/SKILL.md
MDC
      info "cursor (project): created ${rules_dir}/${SKILL_NAME}.mdc"
    else
      info "cursor (project): ${rules_dir}/${SKILL_NAME}.mdc already exists"
    fi
  else
    local rules_dir="$HOME/.cursor/rules"
    mkdir -p "$rules_dir"
    if [[ ! -f "${rules_dir}/${SKILL_NAME}.mdc" ]]; then
      cat > "${rules_dir}/${SKILL_NAME}.mdc" <<MDC
---
description: Autonomous collision-aware SemVer tag resolver
globs:
alwaysApply: false
---
@file ${SKILL_SRC}/SKILL.md
MDC
      info "cursor (global): created ${rules_dir}/${SKILL_NAME}.mdc"
    else
      info "cursor (global): ${rules_dir}/${SKILL_NAME}.mdc already exists"
    fi
  fi
}

install_aider() {
  local conventions
  if [[ -n "$PROJECT" ]]; then
    conventions="${PROJECT}/.aider.conf.yml"
    info "aider (project): add to ${conventions}:"
  else
    conventions="$HOME/.aider.conf.yml"
    info "aider (global): add to ${conventions}:"
  fi
  if [[ -f "$conventions" ]] && grep -q "$SKILL_SRC/SKILL.md" "$conventions" 2>/dev/null; then
    info "aider: already configured"
  else
    info "  read: [\"${SKILL_SRC}/SKILL.md\"]"
    warn "aider requires manual config — add the line above to ${conventions}"
  fi
}

install_windsurf() {
  if [[ -n "$PROJECT" ]]; then
    local rules_dir="${PROJECT}/.windsurf/rules"
    mkdir -p "$rules_dir"
    if [[ ! -f "${rules_dir}/${SKILL_NAME}.md" ]]; then
      ln -s "${SKILL_SRC}/SKILL.md" "${rules_dir}/${SKILL_NAME}.md"
      info "windsurf (project): linked ${rules_dir}/${SKILL_NAME}.md"
    else
      info "windsurf (project): ${rules_dir}/${SKILL_NAME}.md already exists"
    fi
  else
    warn "windsurf: global rules not supported — use --project"
  fi
}

# ── dispatch ─────────────────────────────────────────────────────────
install_for() {
  case "$1" in
    claude-code) install_claude_code ;;
    cursor)      install_cursor ;;
    aider)       install_aider ;;
    windsurf)    install_windsurf ;;
    *) warn "unknown agent: $1" ;;
  esac
}

if [[ -n "$AGENT" ]]; then
  install_for "$AGENT"
else
  # auto-detect
  FOUND=0
  if command -v claude &>/dev/null || [[ -d "$HOME/.claude" ]]; then
    install_for claude-code; FOUND=1
  fi
  if command -v cursor &>/dev/null || [[ -d "$HOME/.cursor" ]]; then
    install_for cursor; FOUND=1
  fi
  if command -v aider &>/dev/null; then
    install_for aider; FOUND=1
  fi
  if command -v windsurf &>/dev/null || [[ -d "$HOME/.windsurf" ]]; then
    install_for windsurf; FOUND=1
  fi
  if [[ $FOUND -eq 0 ]]; then
    warn "no agents detected — skill cloned to ${CLONE_DIR}"
    info "run with --agent <name> to wire up manually"
  fi
fi

info "done. skill source: ${SKILL_SRC}"
info "update: git -C ${CLONE_DIR} pull"
