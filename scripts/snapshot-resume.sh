#!/usr/bin/env bash
set -u

# snapshot-resume.sh save <phase> [execution-state-path] [agent-role] [trigger]
# snapshot-resume.sh restore <phase> [preferred-role]
# Save: snapshot execution state + git context for crash recovery.
# Restore: find latest snapshot for a phase.
# Snapshots: .vbw-planning/.snapshots/{phase}-{timestamp}.json
# Max 10 per phase (prunes oldest). Fail-open: exit 0 always.

if [ $# -lt 2 ]; then
  exit 0
fi

ACTION="$1"
PHASE="$2"

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"
SNAPSHOTS_DIR="${PLANNING_DIR}/.snapshots"

# Check feature flag
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  ENABLED=$(jq -r '.v3_snapshot_resume // false' "$CONFIG_PATH" 2>/dev/null || echo "false")
  [ "$ENABLED" != "true" ] && exit 0
fi

case "$ACTION" in
  save)
    STATE_PATH="${3:-.vbw-planning/.execution-state.json}"
    mkdir -p "$SNAPSHOTS_DIR" 2>/dev/null || exit 0
    [ ! -f "$STATE_PATH" ] && exit 0

    TS=$(date -u +"%Y%m%dT%H%M%S" 2>/dev/null || echo "unknown")
    SNAPSHOT_FILE="${SNAPSHOTS_DIR}/${PHASE}-${TS}.json"

    # Optional agent metadata
    AGENT_ROLE="${4:-}"
    if [ -z "$AGENT_ROLE" ]; then
      AGENT_ROLE=$(cat .vbw-planning/.active-agent 2>/dev/null || echo "unknown")
    fi
    TRIGGER="${5:-unknown}"

    # Build snapshot: execution state + git log + timestamp + metadata
    GIT_LOG=$(git log --oneline -5 2>/dev/null || echo "no git")
    GIT_LOG_JSON=$(echo "$GIT_LOG" | jq -R '.' | jq -s '.' 2>/dev/null) || GIT_LOG_JSON="[]"

    EXEC_STATE=$(cat "$STATE_PATH" 2>/dev/null) || EXEC_STATE="{}"

    jq -n \
      --arg snapshot_ts "$TS" \
      --argjson phase "$PHASE" \
      --argjson execution_state "$EXEC_STATE" \
      --argjson recent_commits "$GIT_LOG_JSON" \
      --arg agent_role "$AGENT_ROLE" \
      --arg trigger "$TRIGGER" \
      '{snapshot_ts: $snapshot_ts, phase: $phase, execution_state: $execution_state, recent_commits: $recent_commits, agent_role: $agent_role, compaction_trigger: $trigger}' \
      > "$SNAPSHOT_FILE" 2>/dev/null || exit 0

    # Prune: keep max 10 snapshots per phase
    # zsh compat: use ls dir | grep to avoid bare glob expansion errors
    # shellcheck disable=SC2010
    SNAP_COUNT=$(ls -1 "${SNAPSHOTS_DIR}/" 2>/dev/null | grep "^${PHASE}-.*\.json$" | wc -l | tr -d ' ')
    if [ "$SNAP_COUNT" -gt 10 ] 2>/dev/null; then
      PRUNE_COUNT=$((SNAP_COUNT - 10))
      # shellcheck disable=SC2010
      ls -1t "${SNAPSHOTS_DIR}/" 2>/dev/null | grep "^${PHASE}-.*\.json$" | tail -n "$PRUNE_COUNT" | while IFS= read -r old; do
        old="${SNAPSHOTS_DIR}/${old}"
        rm -f "$old" 2>/dev/null || true
      done
    fi

    echo "$SNAPSHOT_FILE"
    ;;

  restore)
    [ ! -d "$SNAPSHOTS_DIR" ] && exit 0

    # Optional role filter: restore latest snapshot from this role when available.
    PREFERRED_ROLE="${3:-}"
    LATEST_NAME=""

    # zsh compat: use ls dir | grep to avoid bare glob expansion errors
    # shellcheck disable=SC2010
    SNAPSHOT_NAMES=$(ls -1t "${SNAPSHOTS_DIR}/" 2>/dev/null | grep "^${PHASE}-.*\.json$")

    if [ -n "$PREFERRED_ROLE" ] && [ "$PREFERRED_ROLE" != "unknown" ] && command -v jq &>/dev/null; then
      while IFS= read -r candidate; do
        [ -z "$candidate" ] && continue
        candidate_path="${SNAPSHOTS_DIR}/${candidate}"
        [ ! -f "$candidate_path" ] && continue
        role=$(jq -r '.agent_role // ""' "$candidate_path" 2>/dev/null || echo "")
        if [ "$role" = "$PREFERRED_ROLE" ]; then
          LATEST_NAME="$candidate"
          break
        fi
      done <<< "$SNAPSHOT_NAMES"
    fi

    if [ -z "$LATEST_NAME" ]; then
      LATEST_NAME=$(echo "$SNAPSHOT_NAMES" | head -1)
    fi

    if [ -n "$LATEST_NAME" ] && [ -f "${SNAPSHOTS_DIR}/${LATEST_NAME}" ]; then
      echo "${SNAPSHOTS_DIR}/${LATEST_NAME}"
    fi
    ;;

  *)
    echo "Unknown action: $ACTION. Valid: save, restore" >&2
    ;;
esac

exit 0
