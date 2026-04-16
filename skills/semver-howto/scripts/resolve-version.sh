#!/usr/bin/env bash
# resolve-version.sh — collision-aware SemVer RC resolver
# Proposes the next available -rc[n] tag scoped to the impact zone.
# See SKILL.md for when/why. This file is the how.
#
# Usage:
#   resolve-version.sh [--paths "p1 p2"] [--promote] [--remote origin] [--help]
#
# Output: single tag on stdout. Diagnostics on stderr.
# Exit 0 = success, 1 = error, 2 = ambiguous (needs human).

set -euo pipefail

# ── defaults ──────────────────────────────────────────────────────────
PATHS=""
PROMOTE=false
REMOTE="origin"
DEFAULT_BRANCH=""

usage() {
  cat >&2 <<'EOF'
resolve-version.sh — propose the next collision-free SemVer RC tag.

FLAGS
  --paths "a b"   Explicit impact-zone paths (space-separated).
                  Default: auto-detect from diff against default branch.
  --promote       Strip -rc suffix from the highest RC for the resolved
                  base. Outputs a clean tag for human review. Does NOT push.
  --remote NAME   Remote to pre-flight against (default: origin).
  --help          This message.

ALGORITHM (autonomous / --promote=false)
  1. Impact Zone: modified paths → nearest tag via git-describe --match.
  2. Parse prefix + MAJOR.MINOR.PATCH from that tag.
  3. Bump: feat: in zone commits → minor, else patch.
  4. Collision walk: increment patch (or RC number) until the candidate
     is free both locally (git tag -l) and remotely (git ls-remote).
  5. Emit <prefix>vX.Y.Z-rc<N> on stdout.

ALGORITHM (--promote)
  1-2. Same as above to resolve prefix + base.
  3.   Find highest -rc<N> for that base.
  4.   Propose clean tag (strip -rc<N>). Does NOT push.
EOF
  exit 0
}

# ── parse args ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paths)   PATHS="$2"; shift 2 ;;
    --promote) PROMOTE=true; shift ;;
    --remote)  REMOTE="$2"; shift 2 ;;
    --help)    usage ;;
    *) echo >&2 "unknown flag: $1"; exit 1 ;;
  esac
done

# ── helpers ───────────────────────────────────────────────────────────
info()  { echo >&2 "[semver] $*"; }
die()   { echo >&2 "[semver] ERROR: $*"; exit 1; }
warn()  { echo >&2 "[semver] WARN: $*"; }

resolve_default_branch() {
  # try symbolic ref first, fall back to common names
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

# tag_exists_local "tag" → 0 if exists
tag_exists_local() { git tag -l "$1" | grep -q .; }

# tag_exists_remote "tag" → 0 if exists
tag_exists_remote() {
  git ls-remote --tags "$REMOTE" "refs/tags/$1" 2>/dev/null | grep -q .
}

# tag_is_taken "tag" → 0 if taken locally or remotely
tag_is_taken() { tag_exists_local "$1" || tag_exists_remote "$1"; }

# ── 1. impact zone ───────────────────────────────────────────────────
if [[ -z "$PATHS" ]]; then
  resolve_default_branch
  MERGE_BASE=$(git merge-base HEAD "${REMOTE}/${DEFAULT_BRANCH}" 2>/dev/null) || true
  if [[ -n "$MERGE_BASE" ]]; then
    PATHS=$(git diff --name-only "${MERGE_BASE}...HEAD" 2>/dev/null || true)
  fi
  # fall back to working-tree changes
  if [[ -z "$PATHS" ]]; then
    PATHS=$(git diff --name-only HEAD 2>/dev/null || true)
    UNSTAGED=$(git ls-files --others --exclude-standard 2>/dev/null || true)
    [[ -n "$UNSTAGED" ]] && PATHS="${PATHS}"$'\n'"${UNSTAGED}"
  fi
  PATHS=$(echo "$PATHS" | sort -u | xargs)
fi

[[ -n "$PATHS" ]] || die "no modified paths detected — nothing to version"
info "impact zone: $PATHS"

# ── 2. nearest tag via describe ──────────────────────────────────────
# shellcheck disable=SC2086
IMPACT_COMMIT=$(git log -1 --format=%H -- $PATHS 2>/dev/null) || true
[[ -n "$IMPACT_COMMIT" ]] || die "no commits found touching impact zone"

NEAREST_TAG=$(git describe --tags --abbrev=0 --match "*v*" "$IMPACT_COMMIT" 2>/dev/null) || true

if [[ -z "$NEAREST_TAG" ]]; then
  # bootstrap: no prior tag in scope
  # try to infer prefix from paths (first directory component)
  PREFIX=""
  MAJOR=0; MINOR=1; PATCH=0
  warn "no prior tag found — bootstrapping at ${PREFIX}v${MAJOR}.${MINOR}.${PATCH}-rc1"
else
  info "nearest tag: $NEAREST_TAG"
  # parse: PREFIX everything before first vN, then MAJOR.MINOR.PATCH
  if [[ "$NEAREST_TAG" =~ ^(.*)(v([0-9]+)\.([0-9]+)\.([0-9]+))(.*) ]]; then
    PREFIX="${BASH_REMATCH[1]}"
    MAJOR="${BASH_REMATCH[3]}"
    MINOR="${BASH_REMATCH[4]}"
    PATCH="${BASH_REMATCH[5]}"
    SUFFIX="${BASH_REMATCH[6]}"
  else
    die "cannot parse semver from tag: $NEAREST_TAG"
  fi
fi

info "parsed: prefix='${PREFIX}' version=${MAJOR}.${MINOR}.${PATCH}"

# ── 3. determine bump ────────────────────────────────────────────────
if [[ "$PROMOTE" == true ]]; then
  # promotion mode — skip bump logic, resolve base from nearest
  TARGET_MAJOR=$MAJOR; TARGET_MINOR=$MINOR; TARGET_PATCH=$PATCH
else
  # read commit subjects in zone since nearest tag
  # shellcheck disable=SC2086
  SUBJECTS=$(git log --format=%s "${NEAREST_TAG:+${NEAREST_TAG}..}HEAD" -- $PATHS 2>/dev/null) || true

  if echo "$SUBJECTS" | grep -qE '^feat(\(.+\))?!?:'; then
    info "bump: minor (feat: detected)"
    TARGET_MAJOR=$MAJOR
    TARGET_MINOR=$((MINOR + 1))
    TARGET_PATCH=0
  else
    info "bump: patch"
    TARGET_MAJOR=$MAJOR
    TARGET_MINOR=$MINOR
    TARGET_PATCH=$((PATCH + 1))
  fi
fi

# ── 4. collision walk ────────────────────────────────────────────────
if [[ "$PROMOTE" == true ]]; then
  # find highest RC for the target base and propose clean tag
  BASE="${PREFIX}v${TARGET_MAJOR}.${TARGET_MINOR}.${TARGET_PATCH}"
  CANDIDATES=$(git tag -l "${BASE}-rc*" | sort -V)
  [[ -n "$CANDIDATES" ]] || die "no RCs found for ${BASE} — nothing to promote"
  HIGHEST_RC=$(echo "$CANDIDATES" | tail -1)
  CLEAN_TAG="${BASE}"
  if tag_is_taken "$CLEAN_TAG"; then
    die "${CLEAN_TAG} already exists — cannot promote"
  fi
  info "promote: ${HIGHEST_RC} → ${CLEAN_TAG}"
  echo "$CLEAN_TAG"
  exit 0
fi

# autonomous mode — walk until we find a free -rc slot
MAX_WALK=50  # safety: don't loop forever
WALK=0
while [[ $WALK -lt $MAX_WALK ]]; do
  BASE="${PREFIX}v${TARGET_MAJOR}.${TARGET_MINOR}.${TARGET_PATCH}"

  # if the clean base tag is taken, skip to next patch
  if tag_is_taken "$BASE"; then
    info "  ${BASE} taken — incrementing patch"
    TARGET_PATCH=$((TARGET_PATCH + 1))
    WALK=$((WALK + 1))
    continue
  fi

  # find existing RCs for this base
  EXISTING_RCS=$(git tag -l "${BASE}-rc*" | sort -V)

  if [[ -n "$EXISTING_RCS" ]]; then
    LAST_RC=$(echo "$EXISTING_RCS" | tail -1)
    # extract RC number
    RC_NUM="${LAST_RC##*-rc}"
    NEXT_RC=$((RC_NUM + 1))
  else
    NEXT_RC=1
  fi

  CANDIDATE="${BASE}-rc${NEXT_RC}"

  # shallow pre-flight against remote
  if tag_exists_remote "$CANDIDATE"; then
    info "  ${CANDIDATE} taken on remote — incrementing RC"
    # re-check with incremented RC by adding it locally as "seen"
    # simplest: just bump RC and retry
    NEXT_RC=$((NEXT_RC + 1))
    CANDIDATE="${BASE}-rc${NEXT_RC}"
    # if still taken, let the loop catch it next iteration
    if tag_is_taken "$CANDIDATE"; then
      TARGET_PATCH=$((TARGET_PATCH + 1))
      WALK=$((WALK + 1))
      continue
    fi
  fi

  info "resolved: ${CANDIDATE}"
  echo "$CANDIDATE"
  exit 0
done

die "exhausted ${MAX_WALK} collision-walk iterations — manual intervention required"
