#!/bin/bash
set -u
# delegated-workflow.sh — Manage delegated workflow markers for delegated paths
#
# Sets/clears/checks .vbw-planning/.delegated-workflow.json so runtime guards
# can enforce actual delegation semantics for execute/fix/debug flows.
#
# Usage:
#   delegated-workflow.sh set <mode> [effort] [delegation_mode] [team_name]
#   delegated-workflow.sh clear
#   delegated-workflow.sh check
#
# Actions:
#   set   — Write marker with mode (execute|fix|debug), optional effort
#           (default: balanced), optional delegation_mode
#           (team|subagent|direct), and optional team_name
#   clear — Remove marker file
#   check — Exit 0 if active, 1 if not active
#
# The marker file is transient (gitignored via planning-git.sh).

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
MARKER_FILE="$PLANNING_DIR/.delegated-workflow.json"

ACTION="${1:-}"
MODE="${2:-}"
EFFORT="${3:-balanced}"
DELEGATION_MODE="${4:-}"
TEAM_NAME="${5:-}"

case "$ACTION" in
  set)
    if [ -z "$MODE" ]; then
      echo "Usage: delegated-workflow.sh set <mode> [effort] [delegation_mode] [team_name]" >&2
      exit 1
    fi
    [ -d "$PLANNING_DIR" ] || { echo "No .vbw-planning/ directory" >&2; exit 1; }
    STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    if command -v jq >/dev/null 2>&1; then
      jq -n \
        --arg mode "$MODE" \
        --arg effort "$EFFORT" \
        --arg delegation_mode "$DELEGATION_MODE" \
        --arg team_name "$TEAM_NAME" \
        --arg started_at "$STARTED_AT" \
        '{
          mode: $mode,
          active: true,
          effort: $effort,
          delegation_mode: $delegation_mode,
          team_name: $team_name,
          started_at: $started_at
        }' \
        > "$MARKER_FILE" 2>/dev/null
    else
      printf '{"mode":"%s","active":true,"effort":"%s","delegation_mode":"%s","team_name":"%s","started_at":"%s"}\n' \
        "$MODE" "$EFFORT" "$DELEGATION_MODE" "$TEAM_NAME" "$STARTED_AT" > "$MARKER_FILE" 2>/dev/null
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
