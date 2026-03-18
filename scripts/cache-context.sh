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

# --- Build hash input from deterministic sources ---
HASH_INPUT="phase=${PHASE}:role=${ROLE}"

# Plan content checksum (if plan exists)
if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
  PLAN_SUM=$(shasum -a 256 "$PLAN_PATH" 2>/dev/null | cut -d' ' -f1 || echo "noplan")
  HASH_INPUT="${HASH_INPUT}:plan=${PLAN_SUM}"
fi

# Changed files list (git diff for delta awareness)
if command -v git &>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
  CHANGED_SUM=$(git diff --name-only HEAD 2>/dev/null | sort | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nogit")
  HASH_INPUT="${HASH_INPUT}:changed=${CHANGED_SUM}"
fi

# Codebase mapping fingerprint (roles with mapping hints need cache invalidation)
if [[ "$ROLE" =~ ^(debugger|dev|qa|lead|architect)$ ]] && [ -d "$PLANNING_DIR/codebase" ]; then
  MAP_SUM=$(ls -la "$PLANNING_DIR/codebase"/*.md 2>/dev/null | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nomap")
  HASH_INPUT="${HASH_INPUT}:codebase=${MAP_SUM}"
fi

# Research file fingerprint (lead context changes when research appears/changes)
if [ "$ROLE" = "lead" ]; then
  # Derive phase directory from plan path or phase number
  PHASE_DIR_CACHE=""
  if [ -n "$PLAN_PATH" ] && [ -f "$PLAN_PATH" ]; then
    PHASE_DIR_CACHE=$(dirname "$PLAN_PATH")
  else
    PADDED_PHASE=$(printf "%02d" "$PHASE" 2>/dev/null || echo "$PHASE")
    PHASE_DIR_CACHE=$(find "$PLANNING_DIR/phases" -maxdepth 1 -type d -name "${PADDED_PHASE}-*" 2>/dev/null | head -1)
  fi
  if [ -n "$PHASE_DIR_CACHE" ] && [ -d "$PHASE_DIR_CACHE" ]; then
    RESEARCH_FILES=$(find "$PHASE_DIR_CACHE" -maxdepth 1 -name "*-RESEARCH.md" 2>/dev/null | sort)
    if [ -n "$RESEARCH_FILES" ]; then
      RESEARCH_SUM=$(cat $RESEARCH_FILES 2>/dev/null | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "noresearch")
      HASH_INPUT="${HASH_INPUT}:research=${RESEARCH_SUM}"
    else
      HASH_INPUT="${HASH_INPUT}:research=none"
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
