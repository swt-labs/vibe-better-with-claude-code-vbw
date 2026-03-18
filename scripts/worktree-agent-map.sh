#!/bin/bash
set -u

# worktree-agent-map.sh — map agent names to git worktree paths
# Interface:
#   worktree-agent-map.sh set <agent-name> <worktree-path>
#   worktree-agent-map.sh get <agent-name>
#   worktree-agent-map.sh clear <agent-name>
# Always exits 0 (fail-open)

CMD="${1:-}"
AGENT="${2:-}"
WORKTREE_PATH="${3:-}"

# Require CMD and AGENT
if [ -z "$CMD" ] || [ -z "$AGENT" ]; then
  exit 0
fi

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
STORAGE_DIR="$PLANNING_DIR/.agent-worktrees"
MAP_FILE="${STORAGE_DIR}/${AGENT}.json"

case "$CMD" in
  set)
    if [ -z "$WORKTREE_PATH" ]; then
      exit 0
    fi
    mkdir -p "$STORAGE_DIR"
    CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    printf '{\n  "agent": "%s",\n  "worktree_path": "%s",\n  "created_at": "%s"\n}\n' \
      "$AGENT" "$WORKTREE_PATH" "$CREATED_AT" > "${MAP_FILE}.tmp"
    mv "${MAP_FILE}.tmp" "$MAP_FILE"
    exit 0
    ;;

  get)
    if [ ! -f "$MAP_FILE" ]; then
      exit 0
    fi
    jq -r '.worktree_path // ""' "$MAP_FILE" 2>/dev/null || true
    exit 0
    ;;

  clear)
    rm -f "$MAP_FILE" 2>/dev/null || true
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
