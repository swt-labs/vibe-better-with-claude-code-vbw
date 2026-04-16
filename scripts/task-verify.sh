#!/bin/bash
set -u
# TaskCompleted hook: Advisory commit verification for execute tasks
# Exit 0 always — commit matching is advisory, never blocking
# Exit 0 on ANY error (fail-open: never block legitimate work)

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

emit_task_verify_advisory() {
  local msg="$1"
  command -v jq &>/dev/null || return 0

  jq -n --arg msg "$msg" '{
    "hookSpecificOutput": {
      "hookEventName": "TaskCompleted",
      "additionalContext": ("TaskCompleted advisory: " + $msg)
    }
  }'
}

# Only apply to VBW contexts
[ ! -d "$PLANNING_DIR" ] && exit 0

# Read stdin to get task context
INPUT=$(cat 2>/dev/null) || exit 0

# Extract task subject/description from TaskCompleted event JSON
TASK_SUBJECT=""
if [ -n "$INPUT" ]; then
  TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject // .task.subject // ""' 2>/dev/null) || true
  if [ -z "$TASK_SUBJECT" ]; then
    TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_description // .task.description // ""' 2>/dev/null) || true
  fi
fi

# Analysis-only tasks (e.g., debugger hypothesis investigation) explicitly
# opt out of commit verification.
if echo "$TASK_SUBJECT" | grep -qi '\[analysis-only\]'; then
  exit 0
fi

# Role-only task subjects are coordination/bookkeeping labels, not implementation
# tasks. Don't block completion on commit-keyword matching for these.
TASK_SUBJECT_CANON=$(echo "$TASK_SUBJECT" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
if echo "$TASK_SUBJECT_CANON" | grep -qE '^@?(team-)?(vbw-)?(lead|dev|qa|scout|debugger|architect)(-[0-9]+)?$'; then
  exit 0
fi

# No task context available — fail open.
[ -z "$TASK_SUBJECT" ] && exit 0

# Only canonical execute-protocol Dev tasks are expected to produce commits.
# Manual/non-code/external tasks should never be blocked by this heuristic.
if ! echo "$TASK_SUBJECT" | grep -qiE '^execute[[:space:]]+[0-9]{2}-[0-9]{2}:[[:space:]]+'; then
  exit 0
fi

# Get recent commits (last 20, within 2 hours)
NOW=$(date +%s 2>/dev/null) || exit 0
# Configurable commit recency window (default: 2 hours)
TWO_HOURS=7200
if command -v jq &>/dev/null && [ -f "$PLANNING_DIR/config.json" ]; then
  _window=$(jq -r '.qa_commit_window_seconds // 7200' "$PLANNING_DIR/config.json" 2>/dev/null)
  [ "${_window:-0}" -gt 0 ] 2>/dev/null && TWO_HOURS="$_window"
fi
RECENT_COMMITS=$(git log --oneline -20 --format="%ct %s" 2>/dev/null) || exit 0

if [ -z "$RECENT_COMMITS" ]; then
  emit_task_verify_advisory "Execute task '$TASK_SUBJECT' completed without any git history to verify against. Completion was allowed because commit verification is advisory for execute tasks."
  exit 0
fi

# Filter to commits within last 2 hours
RECENT_MESSAGES=""
while IFS= read -r line; do
  COMMIT_TS=$(echo "$line" | cut -d' ' -f1)
  COMMIT_MSG=$(echo "$line" | cut -d' ' -f2-)
  if [ -n "$COMMIT_TS" ] && [ "$COMMIT_TS" -gt 0 ] 2>/dev/null; then
    AGE=$(( NOW - COMMIT_TS ))
    if [ "$AGE" -le "$TWO_HOURS" ]; then
      RECENT_MESSAGES="${RECENT_MESSAGES}${COMMIT_MSG}
"
    fi
  fi
done <<< "$RECENT_COMMITS"

if [ -z "$RECENT_MESSAGES" ]; then
  emit_task_verify_advisory "Execute task '$TASK_SUBJECT' completed without a recent commit in the configured window. Completion was allowed because commit verification is advisory for execute tasks."
  exit 0
fi

# Extract keywords from task subject (words > 3 chars, lowercased, max 8)
# Filter out common stop words that cause false positive matches
STOP_WORDS="^(that|this|with|from|have|been|will|would|should|could|their|them|then|than|when|what|which|where|were|some|each|into|also|more|over|only|does|make|like|just|most|well|very|much|such|even|execute|implement|create|update|wire|build|task|plan)$"
KEYWORDS=$(echo "$TASK_SUBJECT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | while read -r word; do
  [ ${#word} -gt 3 ] && echo "$word"
done | grep -Ev "$STOP_WORDS" | head -8)

if [ -z "$KEYWORDS" ]; then
  # No usable keywords extracted, allow (fail-open)
  exit 0
fi

# Count total keywords
KEYWORD_COUNT=$(echo "$KEYWORDS" | wc -l | tr -d ' ')

# Determine minimum match threshold
MIN_MATCHES=2
if [ "$KEYWORD_COUNT" -le 2 ]; then
  MIN_MATCHES=1
fi

# Count how many keywords appear in recent commit messages
MATCH_COUNT=0
LOWER_MESSAGES=$(echo "$RECENT_MESSAGES" | tr '[:upper:]' '[:lower:]')

while IFS= read -r keyword; do
  [ -z "$keyword" ] && continue
  if echo "$LOWER_MESSAGES" | grep -q "$keyword"; then
    MATCH_COUNT=$(( MATCH_COUNT + 1 ))
  fi
done <<< "$KEYWORDS"

if [ "$MATCH_COUNT" -ge "$MIN_MATCHES" ]; then
  exit 0
fi

emit_task_verify_advisory "Execute task '$TASK_SUBJECT' completed without a recent matching commit (matched $MATCH_COUNT/$KEYWORD_COUNT keywords, needed $MIN_MATCHES). Completion was allowed because commit verification is advisory for execute tasks."
exit 0
