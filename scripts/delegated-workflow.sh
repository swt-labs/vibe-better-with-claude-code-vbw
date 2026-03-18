#!/bin/bash
set -u
# delegated-workflow.sh — Manage delegated workflow markers for ad-hoc paths
#
# Sets/clears/checks .vbw-planning/.delegated-workflow.json so the file-guard
# PreToolUse hook can enforce delegation for /vbw:fix and /vbw:debug.
#
# Usage:
#   delegated-workflow.sh set <mode> [effort]
#   delegated-workflow.sh clear
#   delegated-workflow.sh check
#
# Actions:
#   set   — Write marker with mode (fix|debug) and optional effort (default: balanced)
#   clear — Remove marker file
#   check — Exit 0 if active, 1 if not active
#
# The marker file is transient (gitignored via planning-git.sh).

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
MARKER_FILE="$PLANNING_DIR/.delegated-workflow.json"

ACTION="${1:-}"
MODE="${2:-}"
EFFORT="${3:-balanced}"

case "$ACTION" in
  set)
    if [ -z "$MODE" ]; then
      echo "Usage: delegated-workflow.sh set <mode> [effort]" >&2
      exit 1
    fi
    [ -d "$PLANNING_DIR" ] || { echo "No .vbw-planning/ directory" >&2; exit 1; }
    STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    if command -v jq >/dev/null 2>&1; then
      jq -n \
        --arg mode "$MODE" \
        --arg effort "$EFFORT" \
        --arg started_at "$STARTED_AT" \
        '{mode: $mode, active: true, effort: $effort, started_at: $started_at}' \
        > "$MARKER_FILE" 2>/dev/null
    else
      printf '{"mode":"%s","active":true,"effort":"%s","started_at":"%s"}\n' \
        "$MODE" "$EFFORT" "$STARTED_AT" > "$MARKER_FILE" 2>/dev/null
    fi
    ;;
  clear)
    rm -f "$MARKER_FILE" 2>/dev/null
    ;;
  check)
    if [ ! -f "$MARKER_FILE" ]; then
      exit 1
    fi
    if command -v jq >/dev/null 2>&1; then
      ACTIVE=$(jq -r '.active // false' "$MARKER_FILE" 2>/dev/null)
      if [ "$ACTIVE" = "true" ]; then
        exit 0
      fi
    else
      # Fallback: file exists = active
      exit 0
    fi
    exit 1
    ;;
  *)
    echo "Usage: delegated-workflow.sh {set|clear|check}" >&2
    exit 1
    ;;
esac
