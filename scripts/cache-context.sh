#!/usr/bin/env bash
set -u

# cache-context.sh <phase> <role> [config-path] [plan-path]
# Computes deterministic cache key for compiled context and checks cache.
# Output: "hit <hash> <cached-path>" or "miss <hash>"
# Exit 0 always (caller decides what to do).
# Uses set -u only (not -e) — this script must never fail fatally.

if [ $# -lt 2 ]; then
  echo "Usage: cache-context.sh <phase> <role> [config-path] [plan-path]" >&2
  exit 1
fi

PHASE="$1"
ROLE="$2"
PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
CONFIG_PATH="${3:-$PLANNING_DIR/config.json}"
PLAN_PATH="${4:-}"
CACHE_DIR="$PLANNING_DIR/.cache/context"

fingerprint_file() {
  local path="$1" missing_label="$2"
  if [ -f "$path" ]; then
    shasum -a 256 "$path" 2>/dev/null | cut -d' ' -f1 || echo "$missing_label"
  else
    echo "$missing_label"
  fi
}

resolve_phase_dir_for_cache() {
  if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
    dirname "$PLAN_PATH"
    return 0
  fi

  local padded_phase
  padded_phase=$(printf "%02d" "$PHASE" 2>/dev/null || echo "$PHASE")
  find "$PLANNING_DIR/phases" -maxdepth 1 -type d -name "${padded_phase}-*" 2>/dev/null | head -1
}

# --- Build hash input from deterministic sources ---
HASH_INPUT="phase=${PHASE}:role=${ROLE}"

# Plan content checksum (if plan exists)
if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
  PLAN_SUM=$(shasum -a 256 "$PLAN_PATH" 2>/dev/null | cut -d' ' -f1 || echo "noplan")
  HASH_INPUT="${HASH_INPUT}:plan=${PLAN_SUM}"
fi

# Changed files list (git diff for delta awareness)
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  CHANGED_SUM=$({
    git diff --binary HEAD 2>/dev/null || true
    git diff --binary --cached 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r file; do
      [ -n "$file" ] || continue
      echo "UNTRACKED:$file"
      if [ -f "$file" ]; then
        shasum -a 256 "$file" 2>/dev/null || true
      fi
    done
  } | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nogit")
  HASH_INPUT="${HASH_INPUT}:changed=${CHANGED_SUM}"
fi

# Core planning artifact fingerprints
ROADMAP_SUM=$(fingerprint_file "$PLANNING_DIR/ROADMAP.md" "noroadmap")
HASH_INPUT="${HASH_INPUT}:roadmap=${ROADMAP_SUM}"

if [[ "$ROLE" =~ ^(lead|qa|scout|architect)$ ]]; then
  REQUIREMENTS_SUM=$(fingerprint_file "$PLANNING_DIR/REQUIREMENTS.md" "noreqs")
  HASH_INPUT="${HASH_INPUT}:requirements=${REQUIREMENTS_SUM}"
fi

if [[ "$ROLE" =~ ^(lead|debugger)$ ]]; then
  STATE_SUM=$(fingerprint_file "$PLANNING_DIR/STATE.md" "nostate")
  HASH_INPUT="${HASH_INPUT}:state=${STATE_SUM}"
fi

if [[ "$ROLE" =~ ^(dev|qa|scout|debugger|architect)$ ]]; then
  CONVENTIONS_SUM=$(fingerprint_file "$PLANNING_DIR/conventions.json" "noconventions")
  HASH_INPUT="${HASH_INPUT}:conventions=${CONVENTIONS_SUM}"
fi

# Codebase mapping fingerprint (roles with mapping hints need cache invalidation)
if [[ "$ROLE" =~ ^(debugger|dev|qa|lead|architect)$ ]] && [ -d "$PLANNING_DIR/codebase" ]; then
  MAP_SUM=$(find "$PLANNING_DIR/codebase" -maxdepth 1 -name '*.md' -print 2>/dev/null | sort | while IFS= read -r map_file; do
    [ -n "$map_file" ] || continue
    printf '%s\n' "$map_file"
    shasum -a 256 "$map_file" 2>/dev/null || true
  done | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nomap")
  HASH_INPUT="${HASH_INPUT}:codebase=${MAP_SUM}"
fi

# Research file fingerprint (roles that include Research Findings)
if [[ "$ROLE" =~ ^(lead|dev|scout|debugger|architect)$ ]]; then
  PHASE_DIR_CACHE=$(resolve_phase_dir_for_cache)
  if [ -n "$PHASE_DIR_CACHE" ] && [ -d "$PHASE_DIR_CACHE" ]; then
    RESEARCH_FILES=$(find "$PHASE_DIR_CACHE" -maxdepth 1 -name "*-RESEARCH.md" 2>/dev/null | sort)
    if [ -n "$RESEARCH_FILES" ]; then
      RESEARCH_SUM=$(printf '%s\n' "$RESEARCH_FILES" | while IFS= read -r research_file; do
        [ -n "$research_file" ] || continue
        printf '%s\n' "$research_file"
        shasum -a 256 "$research_file" 2>/dev/null || true
      done | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "noresearch")
      HASH_INPUT="${HASH_INPUT}:research=${RESEARCH_SUM}"
    else
      HASH_INPUT="${HASH_INPUT}:research=none"
    fi
  fi
fi

# Delta fingerprint (roles that include changed files / code slices)
if [[ "$ROLE" =~ ^(dev|scout|debugger)$ ]] && [ -f "${0%/*}/delta-files.sh" ]; then
  PHASE_DIR_CACHE=$(resolve_phase_dir_for_cache)
  if [ -n "$PHASE_DIR_CACHE" ] && [ -d "$PHASE_DIR_CACHE" ]; then
    DELTA_FILES=$(bash "${0%/*}/delta-files.sh" "$PHASE_DIR_CACHE" "$PLAN_PATH" 2>/dev/null || true)
    if [ -n "$DELTA_FILES" ]; then
      DELTA_LIST_SUM=$(printf '%s\n' "$DELTA_FILES" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nodelta")
      DELTA_CONTENT_SUM=$(printf '%s\n' "$DELTA_FILES" | while IFS= read -r file; do
        [ -n "$file" ] || continue
        echo "FILE:$file"
        if [ -f "$file" ]; then
          shasum -a 256 "$file" 2>/dev/null || true
        else
          echo "missing"
        fi
      done | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nodeltacontent")
      HASH_INPUT="${HASH_INPUT}:delta-list=${DELTA_LIST_SUM}:delta-content=${DELTA_CONTENT_SUM}"
    else
      HASH_INPUT="${HASH_INPUT}:delta-list=none:delta-content=none"
    fi
  fi
fi

# Rolling summary fingerprint
ROLLING_PATH="$PLANNING_DIR/ROLLING-CONTEXT.md"
if command -v jq &>/dev/null && [ -f "$CONFIG_PATH" ]; then
  ROLLING_ENABLED=$(jq -r 'if .rolling_summary != null then .rolling_summary elif .v3_rolling_summary != null then .v3_rolling_summary else false end' "$CONFIG_PATH" 2>/dev/null || echo "false")
  if [ "$ROLLING_ENABLED" = "true" ] && [ -f "$ROLLING_PATH" ]; then
    ROLLING_SUM=$(shasum -a 256 "$ROLLING_PATH" 2>/dev/null | cut -d' ' -f1 || echo "norolling")
    HASH_INPUT="${HASH_INPUT}:rolling=${ROLLING_SUM}"
  fi
fi

# Milestone context fingerprint
MILESTONE_CONTEXT_PATH="$PLANNING_DIR/CONTEXT.md"
if [ -f "$MILESTONE_CONTEXT_PATH" ]; then
  MILESTONE_SUM=$(shasum -a 256 "$MILESTONE_CONTEXT_PATH" 2>/dev/null | cut -d' ' -f1 || echo "nomilestone")
  HASH_INPUT="${HASH_INPUT}:milestone=${MILESTONE_SUM}"
fi

# --- Compute final hash ---
HASH=$(printf '%s' "$HASH_INPUT" | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "")

if [ -z "$HASH" ]; then
  echo "miss nohash"
  exit 0
fi

# Truncate to 16 chars for shorter filenames
HASH="${HASH:0:16}"

CACHED_FILE="${CACHE_DIR}/${HASH}.md"

# --- Check cache ---
if [ -f "$CACHED_FILE" ]; then
  echo "hit ${HASH} ${CACHED_FILE}"
else
  echo "miss ${HASH}"
fi
