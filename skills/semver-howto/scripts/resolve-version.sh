#!/usr/bin/env bash
# resolve-version.sh — collision-aware SemVer RC resolver
#
# Default: proposes tags (dry-run). Use --tag/--release to act.
#
# Output: one proposed tag per line on stdout. Diagnostics on stderr.
# Exit 0 = success, 1 = error.

set -euo pipefail

PREFIX=""
PREFIX_SET=false
TAG_VERSION=""
RELEASE_VERSION=""
PROMOTE=false
BUMP=""
REMOTE="origin"

usage() {
  cat >&2 <<'EOF'
resolve-version.sh — propose or create collision-free SemVer tags.

MODES
  (default)             Propose next RC tag(s). Dry-run, no side effects.
  --tag VERSION         Create and push a specific RC tag.
  --release VERSION     Create and push a specific clean tag.
  --promote             Promote highest RC to clean release tag.

FLAGS
  --prefix NAME   Scope to a single module prefix (e.g. "billing/").
  --minor         Force minor bump (overrides commit-message detection).
  --patch         Force patch bump (overrides commit-message detection).
  --remote NAME   Remote to pre-flight against (default: origin).
  --help          This message.
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)  PREFIX="$2"; PREFIX_SET=true; shift 2 ;;
    --tag)     TAG_VERSION="$2"; shift 2 ;;
    --release) RELEASE_VERSION="$2"; shift 2 ;;
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

# fetch latest refs + tags so we never tag a stale commit
info "fetching ${REMOTE}..."
git fetch "$REMOTE" --tags --quiet 2>/dev/null || die "fetch failed — check network/remote"

# resolve target ref — always the remote default branch HEAD
resolve_target() {
  local branch
  branch=$(git symbolic-ref "refs/remotes/${REMOTE}/HEAD" 2>/dev/null \
    | sed "s|refs/remotes/${REMOTE}/||") || true
  if [[ -z "$branch" ]]; then
    for b in main master; do
      if git rev-parse --verify "${REMOTE}/${b}" &>/dev/null; then
        branch="$b"; break
      fi
    done
  fi
  [[ -n "$branch" ]] || die "cannot determine default branch"
  echo "${REMOTE}/${branch}"
}

TARGET_REF=$(resolve_target)
info "target: ${TARGET_REF}"

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

create_and_push() {
  local version="$1"
  # TODO: add retry/walk on collision — currently dies if tag exists.
  # Consider: push first, handle rejection, retry with next version.
  if tag_is_taken "$version"; then
    die "${version} already exists"
  fi
  git tag "$version" "$TARGET_REF"
  git push "$REMOTE" "$version"
  info "tagged and pushed: ${version} (at ${TARGET_REF})"
  echo "$version"
}

# ── tag: create a specific RC tag ────────────────────────────────────
if [[ -n "$TAG_VERSION" ]]; then
  [[ "$TAG_VERSION" == *-rc* ]] || die "--tag only creates RC tags: ${TAG_VERSION}"
  create_and_push "$TAG_VERSION"
  exit 0
fi

# ── release: create a specific clean tag ─────────────────────────────
if [[ -n "$RELEASE_VERSION" ]]; then
  [[ "$RELEASE_VERSION" != *-rc* ]] || die "--release creates clean tags only: ${RELEASE_VERSION}"
  create_and_push "$RELEASE_VERSION"
  exit 0
fi

# ── promote: highest RC → clean tag ─────────────────────────────────
if [[ "$PROMOTE" == true ]]; then
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
  create_and_push "$CLEAN_TAG"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════
# RESOLVE MODE (dry-run) — propose tags, no side effects
# ══════════════════════════════════════════════════════════════════════

# latest_tags → one line per prefix: "prefix|tag" (highest version per prefix)
latest_tags() {
  local all_tags tag prefix seen=""
  all_tags=$(git tag --merged "$TARGET_REF" --sort=-version:refname | grep -E '(^|/)v[0-9]+\.[0-9]+\.[0-9]+') || true
  [[ -z "$all_tags" ]] && return
  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    [[ "$tag" =~ ^(.*)(v[0-9]+\.[0-9]+\.[0-9]+) ]] || continue
    prefix="${BASH_REMATCH[1]}"
    echo "$seen" | grep -qF "|${prefix}|" && continue
    seen="${seen}|${prefix}|"
    echo "${prefix}|${tag}"
  done <<< "$all_tags"
}

repo_has_prefixed_tags() {
  git tag -l "*/v*" | grep -q . 2>/dev/null
}

# ── 1. list latest tags ─────────────────────────────────────────────
TAG_LIST=$(latest_tags)

if [[ -z "$TAG_LIST" ]]; then
  info "no tags found — bootstrap"
  echo "${PREFIX}v0.1.0-rc1"
  exit 0
fi

info "latest tags:"
echo "$TAG_LIST" | while IFS='|' read -r _ t; do info "  ${t}"; done

# ── 2. diff from nearest tag to HEAD ────────────────────────────────
NEWEST_TAG=""
SMALLEST_DIST=999999
while IFS='|' read -r _ t; do
  dist=$(git rev-list --count "${t}..${TARGET_REF}" 2>/dev/null) || continue
  if [[ "$dist" -gt 0 && "$dist" -lt "$SMALLEST_DIST" ]]; then
    SMALLEST_DIST=$dist
    NEWEST_TAG="$t"
  fi
done <<< "$TAG_LIST"

DIFF_PATHS=""
if [[ -n "$NEWEST_TAG" ]]; then
  DIFF_PATHS=$(git diff --name-only "${NEWEST_TAG}..${TARGET_REF}" 2>/dev/null | sort -u | xargs)
fi

if [[ -z "$DIFF_PATHS" ]]; then
  FIRST_TAG=$(echo "$TAG_LIST" | head -1 | cut -d'|' -f2)
  info "no changes since ${FIRST_TAG}"
  echo "$FIRST_TAG"
  exit 0
fi

info "changes since ${NEWEST_TAG}: $DIFF_PATHS"

# ── 3. group by module (only if prefixed tags exist) ─────────────────
MODULE_LIST=""
PREFIXED=$(repo_has_prefixed_tags && echo true || echo false)

if [[ "$PREFIXED" == true ]]; then
  flat_paths=""
  for path in $DIFF_PATHS; do
    root="${path%%/*}"
    if git tag -l "${root}/v*" | grep -q . 2>/dev/null; then
      mod="${root}/"
      existing=$(echo "$MODULE_LIST" | grep "^${mod}|" | head -1 | cut -d'|' -f2- || true)
      MODULE_LIST=$(echo "$MODULE_LIST" | grep -v "^${mod}|" || true)
      MODULE_LIST="${MODULE_LIST}"$'\n'"${mod}|${existing} ${path}"
    else
      flat_paths="${flat_paths} ${path}"
    fi
  done
  [[ -n "$flat_paths" ]] && MODULE_LIST="${MODULE_LIST}"$'\n'"|${flat_paths}"
  MODULE_LIST=$(echo "$MODULE_LIST" | sed '/^$/d')
else
  MODULE_LIST="|${DIFF_PATHS}"
fi

if [[ "$PREFIX_SET" == true ]]; then
  filtered=$(echo "$MODULE_LIST" | grep -F "${PREFIX}|" | grep "^${PREFIX}|" || true)
  if [[ -z "$filtered" ]]; then
    info "no changes for prefix ${PREFIX}"
    PTAG=""
    while IFS='|' read -r tp tt; do
      [[ "$tp" == "$PREFIX" ]] && PTAG="$tt" && break
    done <<< "$TAG_LIST"
    echo "${PTAG:-none}"
    exit 0
  fi
  MODULE_LIST="$filtered"
fi

# ── 4. resolve per module ────────────────────────────────────────────
resolve_module() {
  local mod_prefix="$1" mod_paths="$2"
  local mod_tag major minor patch bump
  local target_major target_minor target_patch

  info "module: ${mod_prefix:-<root>}"

  mod_tag=""
  while IFS='|' read -r tp tt; do
    if [[ "$tp" == "$mod_prefix" ]]; then
      mod_tag="$tt"
      break
    fi
  done <<< "$TAG_LIST"

  if [[ -z "$mod_tag" ]]; then
    echo "${mod_prefix}v0.1.0-rc1"
    return
  fi

  parse_tag "$mod_tag"
  major=$MAJOR; minor=$MINOR; patch=$PATCH
  info "  latest: ${mod_tag}"

  bump="$BUMP"
  if [[ -z "$bump" ]]; then
    local subjects
    # shellcheck disable=SC2086
    subjects=$(git log --format=%s "${mod_tag}..${TARGET_REF}" -- $mod_paths 2>/dev/null) || true
    if echo "$subjects" | grep -qE '^feat(\(.+\))?!?:'; then
      bump="minor"
    else
      bump="patch"
    fi
  fi

  if [[ "$bump" == "minor" ]]; then
    info "  bump: minor"
    target_major=$major; target_minor=$((minor + 1)); target_patch=0
  else
    info "  bump: patch"
    target_major=$major; target_minor=$minor; target_patch=$((patch + 1))
  fi

  local base candidate walk=0
  while [[ $walk -lt 50 ]]; do
    base="${mod_prefix}v${target_major}.${target_minor}.${target_patch}"

    if tag_is_taken "$base"; then
      info "  WARNING: ${base} already exists — may need cleanup if unexpected"
      info "  incrementing to next patch..."
      target_patch=$((target_patch + 1))
      walk=$((walk + 1))
      continue
    fi

    local existing_rcs last_rc rc_num next_rc
    existing_rcs=$(git tag -l "${base}-rc*" | sort -V)
    if [[ -n "$existing_rcs" ]]; then
      last_rc=$(echo "$existing_rcs" | tail -1)
      rc_num="${last_rc##*-rc}"
      next_rc=$((rc_num + 1))
    else
      next_rc=1
    fi

    candidate="${base}-rc${next_rc}"

    if tag_exists_remote "$candidate"; then
      info "  ${candidate} taken on remote — incrementing RC"
      next_rc=$((next_rc + 1))
      candidate="${base}-rc${next_rc}"
      if tag_is_taken "$candidate"; then
        target_patch=$((target_patch + 1))
        walk=$((walk + 1))
        continue
      fi
    fi

    info "  proposed: ${candidate}"
    echo "$candidate"
    return
  done

  die "exhausted collision walk for ${mod_prefix}"
}

while IFS='|' read -r mod_prefix mod_paths; do
  resolve_module "$mod_prefix" "$mod_paths"
done <<< "$MODULE_LIST"