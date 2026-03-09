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

# --- Worktree context injection ---
WORKTREE_CONTEXT=""
if echo "$ROLE" | grep -q "vbw-dev\|vbw-debugger"; then
  AGENT_NAME_COMPACT=$(echo "$INPUT" | jq -r '.agent_name // .agentName // ""' 2>/dev/null) || AGENT_NAME_COMPACT=""
  AGENT_NAME_SHORT=$(echo "$AGENT_NAME_COMPACT" | sed 's/.*vbw-//')
  WORKTREE_MAP_FILE=".vbw-planning/.agent-worktrees/${AGENT_NAME_SHORT}.json"
  if [ -f "$WORKTREE_MAP_FILE" ]; then
    WT_PATH=$(jq -r '.worktree_path // ""' "$WORKTREE_MAP_FILE" 2>/dev/null) || WT_PATH=""
    if [ -n "$WT_PATH" ]; then
      WORKTREE_CONTEXT=" Worktree working directory: ${WT_PATH}. All file operations must use this path."
    fi
  fi
fi

# Teammate task recovery hint
TASK_HINT=""
if [ -n "$ROLE" ] && [ "$ROLE" != "unknown" ]; then
  TASK_HINT=" If you are a teammate, call TaskGet for your assigned task ID to restore your current objective."
fi

# --- Orchestrator resume hint (non-agent sessions only) ---
# When the orchestrator (ROLE="" or "unknown") compacts mid-command, it loses
# the vibe.md instructions and may try Skill('vbw:vibe') which is blocked by
# disable-model-invocation. Detect active mode from disk state and emit a
# targeted resume instruction with the exact file path and mode section.
ORCH_RESUME=""
if [ -z "$ROLE" ] || [ "$ROLE" = "unknown" ]; then
  VIBE_CMD_PATH="$SCRIPT_DIR/../commands/vibe.md"
  if [ -f "$VIBE_CMD_PATH" ]; then
    VIBE_CANONICAL=$(cd "$(dirname "$VIBE_CMD_PATH")" && echo "$(pwd)/$(basename "$VIBE_CMD_PATH")") || VIBE_CANONICAL=""
    [ -n "$VIBE_CANONICAL" ] && VIBE_CMD_PATH="$VIBE_CANONICAL"
  fi

  ACTIVE_MODE=""
  PD_AUTONOMY=""
  # Detect from execution state first (most specific)
  if [ -f ".vbw-planning/.execution-state.json" ] && command -v jq &>/dev/null; then
    EXEC_STATUS=$(jq -r '.status // ""' ".vbw-planning/.execution-state.json" 2>/dev/null)
    EXEC_PHASE=$(jq -r '.phase // ""' ".vbw-planning/.execution-state.json" 2>/dev/null)
    case "$EXEC_STATUS" in
      running)  ACTIVE_MODE="Execute" ;;
      *)        ACTIVE_MODE=""; EXEC_PHASE="" ;; # clear both, fall through to phase-detect
    esac
  fi

  # Fall back to phase-detect for non-execution modes
  if [ -z "$ACTIVE_MODE" ] && [ -f "$SCRIPT_DIR/phase-detect.sh" ]; then
    PD_OUT=$(bash "$SCRIPT_DIR/phase-detect.sh" 2>/dev/null) || PD_OUT=""
    if [ -n "$PD_OUT" ]; then
      PD_STATE=$(echo "$PD_OUT" | grep -m1 '^next_phase_state=' | sed 's/^[^=]*=//')
      PD_PHASE=$(echo "$PD_OUT" | grep -m1 '^next_phase=' | sed 's/^[^=]*=//')
      PD_PROJECT=$(echo "$PD_OUT" | grep -m1 '^project_exists=' | sed 's/^[^=]*=//')
      PD_MS_UAT=$(echo "$PD_OUT" | grep -m1 '^milestone_uat_issues=' | sed 's/^[^=]*=//')
      PD_AUTONOMY=$(echo "$PD_OUT" | grep -m1 '^config_autonomy=' | sed 's/^[^=]*=//')
      case "$PD_STATE" in
        needs_uat_remediation)   ACTIVE_MODE="UAT Remediation" ;;
        needs_reverification)    ACTIVE_MODE="Verify" ;;
        needs_discussion)        ACTIVE_MODE="Discuss" ;;
        needs_plan_and_execute)  ACTIVE_MODE="Plan" ;;
        needs_execute)           ACTIVE_MODE="Execute" ;;
        all_done)
          if [ "$PD_MS_UAT" = "true" ]; then
            ACTIVE_MODE="Milestone UAT Recovery"
          else
            ACTIVE_MODE="Archive"
          fi
          ;;
        no_phases)
          if [ "$PD_PROJECT" = "false" ]; then
            ACTIVE_MODE="Bootstrap"
          elif [ "$PD_MS_UAT" = "true" ]; then
            ACTIVE_MODE="Milestone UAT Recovery"
          else
            ACTIVE_MODE="Scope"
          fi
          ;;
      esac
      : "${EXEC_PHASE:=$PD_PHASE}"
    fi
  fi

  # Filter sentinel values from phase display
  case "${EXEC_PHASE:-}" in none|"") EXEC_PHASE="" ;; esac

  if [ -n "$ACTIVE_MODE" ] && [ -f "$VIBE_CMD_PATH" ]; then
    ORCH_RESUME=" ORCHESTRATOR RESUME: You were executing /vbw:vibe ${ACTIVE_MODE} mode${EXEC_PHASE:+ for Phase ${EXEC_PHASE}}. Do NOT call Skill('vbw:vibe') or any Skill('vbw:*') — it will fail (disable-model-invocation). Instead, use the Read tool to re-read ${VIBE_CMD_PATH} and jump directly to the '### Mode: ${ACTIVE_MODE}' section. Resume from where you left off using your compacted summary context.${PD_AUTONOMY:+ Autonomy: ${PD_AUTONOMY}.}"
  fi
fi

jq -n --arg role "${ROLE:-unknown}" --arg files "$FILES" --arg snap "${SNAPSHOT_CONTEXT:-}" --arg taskhint "${TASK_HINT:-}" --arg worktree "${WORKTREE_CONTEXT:-}" --arg orchresume "${ORCH_RESUME:-}" '{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": ("Context was compacted. Agent role: " + $role + ". Re-read these key files from disk: " + $files + $snap + $taskhint + $worktree + $orchresume)
  }
}'

exit 0
