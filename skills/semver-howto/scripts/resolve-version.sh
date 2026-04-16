#!/usr/bin/env bash
# resolve-version.sh — collision-aware SemVer RC resolver
#
# Usage:
#   resolve-version.sh [--paths "p1 p2"] [--prefix mod/] [--tag] [--minor|--patch] [--promote] [--help]
#
# Output: single tag on stdout. Diagnostics on stderr.
# Exit 0 = success, 1 = error, 2 = ambiguous (needs human).

set -euo pipefail

PATHS=""
PREFIX=""
PREFIX_SET=false
PROMOTE=false
TAG=false
BUMP=""
REMOTE="origin"
DEFAULT_BRANCH=""

usage() {
  cat >&2 <<'EOF'
resolve-version.sh — propose the next collision-free SemVer RC tag.

FLAGS
  --paths "a b"   Explicit impact-zone paths (space-separated).
                  Default: auto-detect from diff against default branch.
  --prefix NAME   Force tag prefix (e.g. "salesforce/"). Default: inferred
                  from impact-zone paths + existing tag patterns.
  --tag           Create the resolved RC tag and push it. RC tags only.
  --minor         Force a minor bump (overrides commit-message detection).
  --patch         Force a patch bump (overrides commit-message detection).
  --promote       Propose clean tag from the highest existing RC.
                  HITL required — never tags or pushes autonomously.
  --remote NAME   Remote to pre-flight against (default: origin).
  --help          This message.

PREFIX INFERENCE
  1. Extract common root directory from impact-zone paths.
  2. If tags matching "<root>/v*" exist → use "<root>/" as prefix.
  3. Otherwise fall back to "" (flat repo, tags like v1.2.3).
  --prefix overrides this entirely.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths)   PATHS="$2"; shift 2 ;;
    --prefix)  PREFIX="$2"; PREFIX_SET=true; shift 2 ;;
    --tag)     TAG=true; shift ;;
    --minor)   BUMP="minor"; shift ;;
    --patch)   BUMP="patch"; shift ;;
    --promote) PROMOTE=true; shift ;;
    --remote)  REMOTE="$2"; shift 2 ;;
    --help)    usage ;;
    *) echo >&2 "unknown flag: $1"; exit 1 ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────
info()  { echo >&2 "[semver] $*"; }
die()   { echo >&2 "[semver] ERROR: $*"; exit 1; }

resolve_default_branch() {
  DEFAULT_BRANCH=$(git symbolic-ref "refs/remotes/${REMOTE}/HEAD" 2>/dev/null \
    | sed "s|refs/remotes/${REMOTE}/||") || true
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    for b in main master; do
      if git rev-parse --verify "${REMOTE}/${b}" &>/dev/null; then
        DEFAULT_BRANCH="$b"; break
      fi
    done
  fi
  [[ -n "$DEFAULT_BRANCH" ]] || die "cannot determine default branch"
}

tag_exists_local()  { git tag -l "$1" | grep -q .; }
tag_exists_remote() { git ls-remote --tags "$REMOTE" "refs/tags/$1" 2>/dev/null | grep -q .; }
tag_is_taken()      { tag_exists_local "$1" || tag_exists_remote "$1"; }

parse_tag() {
  if [[ "$1" =~ ^(.*)(v([0-9]+)\.([0-9]+)\.([0-9]+))(.*) ]]; then
    PREFIX="${BASH_REMATCH[1]}"
    MAJOR="${BASH_REMATCH[3]}"
    MINOR="${BASH_REMATCH[4]}"
    PATCH="${BASH_REMATCH[5]}"
  else
    die "cannot parse semver from tag: $1"
  fi
}

# infer_prefix "path1 path2 ..." → sets PREFIX if not already forced
infer_prefix() {
  [[ "$PREFIX_SET" == true ]] && return

  local paths="$1"
  # extract first path component from each path, find common root
  local roots root
  roots=$(echo "$paths" | tr ' ' '\n' | sed 's|/.*||' | sort -u)
  local count
  count=$(echo "$roots" | wc -l | tr -d ' ')

  if [[ "$count" -eq 1 ]]; then
    root=$(echo "$roots" | head -1)
    # check if module-prefixed tags exist for this root
    if git tag -l "${root}/v*" | grep -q .; then
      PREFIX="${root}/"
      info "inferred prefix: ${PREFIX} (from existing tags)"
      return
    fi
    # check remote too
    if git ls-remote --tags "$REMOTE" "refs/tags/${root}/v*" 2>/dev/null | grep -q .; then
      PREFIX="${root}/"
      info "inferred prefix: ${PREFIX} (from remote tags)"
      return
    fi
  fi

  # no module prefix found — flat repo
  PREFIX=""
}

# ── promote ──────────────────────────────────────────────────────────
if [[ "$PROMOTE" == true ]]; then
  # if prefix known, scope to it; otherwise scan all
  if [[ "$PREFIX_SET" == true ]]; then
    LATEST_RC=$(git tag -l "${PREFIX}v*-rc*" | sort -V | tail -1)
  else
    LATEST_RC=$(git tag -l "*v*-rc*" | sort -V | tail -1)
  fi
  if [[ -z "$LATEST_RC" ]]; then
    info "no RC tags found — nothing to promote"
    echo "none"
    exit 0
  fi

  parse_tag "$LATEST_RC"
  CLEAN_TAG="${PREFIX}v${MAJOR}.${MINOR}.${PATCH}"

  if tag_is_taken "$CLEAN_TAG"; then
    info "${CLEAN_TAG} already released"
    echo "$CLEAN_TAG"
    exit 0
  fi
  info "promote: ${LATEST_RC} → ${CLEAN_TAG}"
  info "HITL REQUIRED — human must approve, tag, and push:"
  info "  git tag ${CLEAN_TAG} ${LATEST_RC}^{} && git push origin ${CLEAN_TAG}"
  echo "$CLEAN_TAG"
  exit 0
fi

# ── detect impact zone ───────────────────────────────────────────────
HAS_CHANGES=true
if [[ -z "$PATHS" ]]; then
  resolve_default_branch
  MERGE_BASE=$(git merge-base HEAD "${REMOTE}/${DEFAULT_BRANCH}" 2>/dev/null) || true
  if [[ -n "$MERGE_BASE" ]]; then
    PATHS=$(git diff --name-only "${MERGE_BASE}...HEAD" 2>/dev/null || true)
  fi
  if [[ -z "$PATHS" ]]; then
    PATHS=$(git diff --name-only HEAD 2>/dev/null || true)
    UNSTAGED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
    [[ -n "$UNSTAGED" ]] && PATHS="${PATHS}"$'\n'"${UNSTAGED}"
  fi
  PATHS=$(echo "$PATHS" | sort -u | xargs)
  [[ -z "$PATHS" ]] && HAS_CHANGES=false
fi

# ── infer prefix from paths ─────────────────────────────────────────
if [[ "$HAS_CHANGES" == true ]]; then
  infer_prefix "$PATHS"
fi

# ── resolve nearest tag ─────────────────────────────────────────────
MATCH_PATTERN="${PREFIX}v*"

if [[ "$HAS_CHANGES" == true ]]; then
  info "impact zone: $PATHS"
  # shellcheck disable=SC2086
  ANCHOR=$(git log -1 --format=%H -- $PATHS 2>/dev/null) || true
else
  ANCHOR=$(git rev-parse HEAD 2>/dev/null) || true
fi
[[ -n "$ANCHOR" ]] || die "no commits found"

NEAREST_TAG=$(git describe --tags --abbrev=0 --match "$MATCH_PATTERN" "$ANCHOR" 2>/dev/null) || true

# ── no tags → bootstrap ─────────────────────────────────────────────
if [[ -z "$NEAREST_TAG" ]]; then
  CANDIDATE="${PREFIX}v0.1.0-rc1"
  info "no prior tag found — bootstrap"
  if [[ "$TAG" == true ]]; then
    git tag "$CANDIDATE"
    git push "$REMOTE" "$CANDIDATE"
    info "tagged and pushed: ${CANDIDATE}"
  fi
  echo "$CANDIDATE"
  exit 0
fi

parse_tag "$NEAREST_TAG"
info "nearest tag: $NEAREST_TAG (${PREFIX}v${MAJOR}.${MINOR}.${PATCH})"

# ── no changes → report current version ─────────────────────────────
if [[ "$HAS_CHANGES" == false ]]; then
  info "no changes detected — current version"
  echo "$NEAREST_TAG"
  exit 0
fi

# ── determine bump ───────────────────────────────────────────────────
if [[ -z "$BUMP" ]]; then
  # shellcheck disable=SC2086
  SUBJECTS=$(git log --format=%s "${NEAREST_TAG}..HEAD" -- $PATHS 2>/dev/null) || true
  if echo "$SUBJECTS" | grep -qE '^feat(\(.+\))?!?:'; then
    BUMP="minor"
  else
    BUMP="patch"
  fi
fi

if [[ "$BUMP" == "minor" ]]; then
  info "bump: minor"
  TARGET_MAJOR=$MAJOR; TARGET_MINOR=$((MINOR + 1)); TARGET_PATCH=0
else
  info "bump: patch"
  TARGET_MAJOR=$MAJOR; TARGET_MINOR=$MINOR; TARGET_PATCH=$((PATCH + 1))
fi

# ── collision walk ───────────────────────────────────────────────────
MAX_WALK=50
WALK=0
while [[ $WALK -lt $MAX_WALK ]]; do
  BASE="${PREFIX}v${TARGET_MAJOR}.${TARGET_MINOR}.${TARGET_PATCH}"

  if tag_is_taken "$BASE"; then
    info "  ${BASE} taken — incrementing patch"
    TARGET_PATCH=$((TARGET_PATCH + 1))
    WALK=$((WALK + 1))
    continue
  fi

  EXISTING_RCS=$(git tag -l "${BASE}-rc*" | sort -V)
  if [[ -n "$EXISTING_RCS" ]]; then
    LAST_RC=$(echo "$EXISTING_RCS" | tail -1)
    RC_NUM="${LAST_RC##*-rc}"
    NEXT_RC=$((RC_NUM + 1))
  else
    NEXT_RC=1
  fi

  CANDIDATE="${BASE}-rc${NEXT_RC}"

  if tag_exists_remote "$CANDIDATE"; then
    info "  ${CANDIDATE} taken on remote — incrementing RC"
    NEXT_RC=$((NEXT_RC + 1))
    CANDIDATE="${BASE}-rc${NEXT_RC}"
    if tag_is_taken "$CANDIDATE"; then
      TARGET_PATCH=$((TARGET_PATCH + 1))
      WALK=$((WALK + 1))
      continue
    fi
  fi

  info "resolved: ${CANDIDATE}"
  if [[ "$TAG" == true ]]; then
    git tag "$CANDIDATE"
    git push "$REMOTE" "$CANDIDATE"
    info "tagged and pushed: ${CANDIDATE}"
  fi
  echo "$CANDIDATE"
  exit 0
done

die "exhausted ${MAX_WALK} collision-walk iterations — manual intervention required"