#!/bin/bash
set -u
# TaskCompleted hook: remind Lead to notify agents whose blockers just cleared
# Outputs additionalContext with unblocked task info
# Exit 0 always (advisory, never blocks)

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

# Only apply to VBW contexts with active teams
[ ! -d "$PLANNING_DIR" ] && exit 0
command -v jq &>/dev/null || exit 0

# Read stdin to get completed task context
INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

# Extract completed task ID
TASK_ID=$(echo "$INPUT" | jq -r '.task_id // .task.id // ""' 2>/dev/null) || exit 0
[ -z "$TASK_ID" ] && exit 0

# Check if any team task list exists (we're in a team context)
# shellcheck source=resolve-claude-dir.sh
. "$(dirname "$0")/resolve-claude-dir.sh"
TEAM_TASKS=""
for d in "$CLAUDE_DIR"/tasks/*/; do
  [ -d "$d" ] && TEAM_TASKS="$d" && break
done
[ -z "$TEAM_TASKS" ] && exit 0

# Scan task files for any that have this task ID in their blockedBy
UNBLOCKED=""
for task_file in "$TEAM_TASKS"*.json; do
  [ -f "$task_file" ] || continue

  # Skip completed/deleted tasks
  STATUS=$(jq -r '.status // ""' "$task_file" 2>/dev/null) || continue
  [ "$STATUS" = "completed" ] || [ "$STATUS" = "deleted" ] && continue

  # Check if this task is blocked by the completed task
  IS_BLOCKED=$(jq -r --arg tid "$TASK_ID" '.blockedBy // [] | map(select(. == $tid)) | length' "$task_file" 2>/dev/null) || continue
  [ "$IS_BLOCKED" -gt 0 ] 2>/dev/null || continue

  # Check if ALL other blockers are also completed
  ALL_CLEAR="true"
  OTHER_BLOCKERS=$(jq -r --arg tid "$TASK_ID" '.blockedBy // [] | map(select(. != $tid)) | .[]' "$task_file" 2>/dev/null) || continue
  for blocker_id in $OTHER_BLOCKERS; do
    [ -z "$blocker_id" ] && continue
    BLOCKER_FILE="$TEAM_TASKS${blocker_id}.json"
    if [ -f "$BLOCKER_FILE" ]; then
      BLOCKER_STATUS=$(jq -r '.status // "pending"' "$BLOCKER_FILE" 2>/dev/null) || true
      [ "$BLOCKER_STATUS" != "completed" ] && ALL_CLEAR="false" && break
    fi
  done

  if [ "$ALL_CLEAR" = "true" ]; then
    TASK_SUBJECT=$(jq -r '.subject // "unknown"' "$task_file" 2>/dev/null) || true
    TASK_OWNER=$(jq -r '.owner // "unassigned"' "$task_file" 2>/dev/null) || true
    TASK_FILE_ID=$(basename "$task_file" .json)
    UNBLOCKED="${UNBLOCKED}Task #${TASK_FILE_ID} (${TASK_SUBJECT}) assigned to ${TASK_OWNER} is now unblocked. "
  fi
done

# If we found unblocked tasks, output advisory context
if [ -n "$UNBLOCKED" ]; then
  jq -n --arg ctx "$UNBLOCKED" '{
    "hookSpecificOutput": {
      "hookEventName": "TaskCompleted",
      "additionalContext": ("BLOCKER CLEARED: " + $ctx + "Send each unblocked agent a message to proceed.")
    }
  }'
fi

exit 0
