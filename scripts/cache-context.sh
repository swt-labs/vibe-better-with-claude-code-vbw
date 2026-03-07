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
CONFIG_PATH="${3:-.vbw-planning/config.json}"
PLAN_PATH="${4:-}"
CACHE_DIR=".vbw-planning/.cache/context"

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
if [[ "$ROLE" =~ ^(debugger|dev|qa|lead|architect)$ ]] && [ -d ".vbw-planning/codebase" ]; then
  MAP_SUM=$(ls -la .vbw-planning/codebase/*.md 2>/dev/null | shasum -a 256 2>/dev/null | cut -d' ' -f1 || echo "nomap")
  HASH_INPUT="${HASH_INPUT}:codebase=${MAP_SUM}"
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
