#!/bin/bash
set -u
# SessionStart(compact) hook: Remind agent to re-read key files after compaction
# Reads compaction context from stdin, detects agent role, suggests re-reads

INPUT=$(cat)

# Clean up cost tracking files and compaction marker (stale after compaction)
# Preserve .active-agent and .active-agent-count — agents may still be running
# after compaction. These are cleaned up by agent-stop.sh and session-stop.sh.
rm -f .vbw-planning/.cost-ledger.json .vbw-planning/.compaction-marker 2>/dev/null

# Try to identify agent role from input context
ROLE=""
for pattern in vbw-lead vbw-dev vbw-qa vbw-scout vbw-debugger vbw-architect vbw-docs; do
  if echo "$INPUT" | grep -qi "$pattern"; then
    ROLE="$pattern"
    break
  fi
done

# Convert plan id (e.g. "05-01") to numeric plan number (e.g. "1")
plan_id_to_num() {
  local plan_id="$1"
  echo "$plan_id" | sed 's/^[0-9]*-//' | sed 's/^0*//' | sed 's/^$/0/'
}

# Build next task id from last completed task id (e.g. 1-1-T3 -> 1-1-T4)
next_task_from_completed() {
  local task_id="$1"
  if [[ "$task_id" =~ ^([0-9]+-[0-9]+-T)([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}$((BASH_REMATCH[2] + 1))"
  fi
}

case "$ROLE" in
  vbw-lead)
    FILES="STATE.md, ROADMAP.md, config.json, and current phase plans"
    ;;
  vbw-dev)
    FILES="your assigned plan file, SUMMARY.md template, and relevant source files"
    ;;
  vbw-qa)
    FILES="SUMMARY.md files under review, verification criteria, and gap reports"
    ;;
  vbw-scout)
    FILES="research notes, REQUIREMENTS.md, and any scout-specific findings"
    ;;
  vbw-debugger)
    FILES="reproduction steps, hypothesis log, and related source files"
    ;;
  vbw-architect)
    FILES="REQUIREMENTS.md, ROADMAP.md, phase structure, and architecture decisions"
    ;;
  *)
    FILES="STATE.md, your assigned task context, and any in-progress files"
    ;;
esac

# --- Restore agent state snapshot ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT_CONTEXT=""
if [ -f ".vbw-planning/.execution-state.json" ] && [ -f "$SCRIPT_DIR/snapshot-resume.sh" ]; then
  SNAP_PHASE=$(jq -r '.phase // ""' ".vbw-planning/.execution-state.json" 2>/dev/null)
  if [ -n "$SNAP_PHASE" ]; then
    SNAP_PATH=$(bash "$SCRIPT_DIR/snapshot-resume.sh" restore "$SNAP_PHASE" "${ROLE:-}" 2>/dev/null) || SNAP_PATH=""
    if [ -n "$SNAP_PATH" ] && [ -f "$SNAP_PATH" ]; then
      SNAP_PLAN=$(jq -r '
        .execution_state.current_plan //
        (
          .execution_state.plans // []
          | map(select(.status == "running" or .status == "pending"))
          | sort_by(.id)
          | .[0].id
        ) //
        (
          .execution_state.plans // []
          | sort_by(.id)
          | .[0].id
        ) //
        "unknown"
      ' "$SNAP_PATH" 2>/dev/null)
      SNAP_STATUS=$(jq -r '.execution_state.status // "unknown"' "$SNAP_PATH" 2>/dev/null)
      SNAP_COMMITS=$(jq -r '.recent_commits | join(", ")' "$SNAP_PATH" 2>/dev/null) || SNAP_COMMITS=""

      # Task-level resume hint: prefer explicit cursor; fallback to event log.
      SNAP_IN_PROGRESS_TASK=$(jq -r '.execution_state.current_task_id // ""' "$SNAP_PATH" 2>/dev/null)
      SNAP_LAST_COMPLETED_TASK=""
      SNAP_NEXT_TASK=""
      if [ -n "$SNAP_PLAN" ] && [ "$SNAP_PLAN" != "unknown" ] && [ -f ".vbw-planning/.events/event-log.jsonl" ] && command -v jq >/dev/null 2>&1; then
        PLAN_NUM=$(plan_id_to_num "$SNAP_PLAN")
        if [ -n "$PLAN_NUM" ] && [[ "$PLAN_NUM" =~ ^[0-9]+$ ]] && [ "$PLAN_NUM" -gt 0 ]; then
          LAST_STARTED_TASK=$(jq -r --argjson phase "$SNAP_PHASE" --argjson plan "$PLAN_NUM" '
            select(.event == "task_started" and .phase == $phase and (.plan // 0) == $plan)
            | .data.task_id // empty
          ' ".vbw-planning/.events/event-log.jsonl" 2>/dev/null | tail -1)

          LAST_COMPLETED_TASK=$(jq -r --argjson phase "$SNAP_PHASE" --argjson plan "$PLAN_NUM" '
            select(.event == "task_completed_confirmed" and .phase == $phase and (.plan // 0) == $plan)
            | .data.task_id // empty
          ' ".vbw-planning/.events/event-log.jsonl" 2>/dev/null | tail -1)

          if [ -z "$SNAP_IN_PROGRESS_TASK" ] && [ -n "$LAST_STARTED_TASK" ] && [ "$LAST_STARTED_TASK" != "$LAST_COMPLETED_TASK" ]; then
            SNAP_IN_PROGRESS_TASK="$LAST_STARTED_TASK"
          fi

          if [ -n "$LAST_COMPLETED_TASK" ]; then
            SNAP_LAST_COMPLETED_TASK="$LAST_COMPLETED_TASK"
            SNAP_NEXT_TASK=$(next_task_from_completed "$LAST_COMPLETED_TASK")
          fi
        fi
      fi

      SNAPSHOT_CONTEXT=" Pre-compaction state: phase=${SNAP_PHASE}, plan=${SNAP_PLAN}, status=${SNAP_STATUS}."
      if [ -n "$SNAP_IN_PROGRESS_TASK" ]; then
        SNAPSHOT_CONTEXT="${SNAPSHOT_CONTEXT} In-progress task before compact: ${SNAP_IN_PROGRESS_TASK}."
      elif [ -n "$SNAP_NEXT_TASK" ]; then
        SNAPSHOT_CONTEXT="${SNAPSHOT_CONTEXT} Resume candidate: ${SNAP_NEXT_TASK}."
      fi
      if [ -n "$SNAP_LAST_COMPLETED_TASK" ]; then
        SNAPSHOT_CONTEXT="${SNAPSHOT_CONTEXT} Last completed task: ${SNAP_LAST_COMPLETED_TASK}."
      fi
      if [ -n "$SNAP_COMMITS" ]; then
        SNAPSHOT_CONTEXT="${SNAPSHOT_CONTEXT} Recent commits: ${SNAP_COMMITS}."
      fi
      TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
      echo "[$TIMESTAMP] Snapshot restored: $SNAP_PATH phase=$SNAP_PHASE" >> ".vbw-planning/.hook-errors.log" 2>/dev/null || true
    fi
  fi
fi

jq -n --arg role "${ROLE:-unknown}" --arg files "$FILES" --arg snap "${SNAPSHOT_CONTEXT:-}" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ("Context was compacted. Agent role: " + $role + ". Re-read these key files from disk: " + $files + $snap)
  }
}'

exit 0
