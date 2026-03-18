#!/bin/bash
set -u
# TaskCompleted hook: Verify a recent git commit exists for the completed task
# Exit 2 = block completion, Exit 0 = allow
# Exit 0 on ANY error (fail-open: never block legitimate work)

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

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
# opt out of the commit requirement via an [analysis-only] tag.
# Checked early — before commit fetching — so these never hit the "no recent
# commits" block even when no code changes exist in the repo.
if echo "$TASK_SUBJECT" | grep -qi '\[analysis-only\]'; then
  exit 0
fi

# Role-only task subjects are coordination/bookkeeping labels, not implementation
# tasks. Don't block completion on commit-keyword matching for these.
TASK_SUBJECT_CANON=$(echo "$TASK_SUBJECT" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')
if echo "$TASK_SUBJECT_CANON" | grep -qE '^@?(team-)?(vbw-)?(lead|dev|qa|scout|debugger|architect)(-[0-9]+)?$'; then
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
  echo "No commits found in repository" >&2
  exit 2
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
  echo "No recent commits found (last commit is over 2 hours old)" >&2
  exit 2
fi

# If no task context available, fall back to original behavior (any recent commit = pass)
if [ -z "$TASK_SUBJECT" ]; then
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

echo "No recent commit found matching task: '$TASK_SUBJECT' (matched $MATCH_COUNT/$KEYWORD_COUNT keywords, needed $MIN_MATCHES)" >&2

# Circuit breaker: if this same subject has already been blocked once, allow it
# on the second attempt. This prevents infinite hook loops where the agent
# responds to the block, triggering another turn, which triggers the hook again.
SEEN_FILE="$PLANNING_DIR/.task-verify-seen"
SUBJECT_HASH=$(printf '%s' "$TASK_SUBJECT" | md5 2>/dev/null || printf '%s' "$TASK_SUBJECT" | md5sum 2>/dev/null | cut -d' ' -f1 || printf '%s' "$TASK_SUBJECT" | cksum 2>/dev/null | cut -d' ' -f1 || echo "${#TASK_SUBJECT}-${TASK_SUBJECT%% *}")
if [ -f "$SEEN_FILE" ] && grep -qFx "$SUBJECT_HASH" "$SEEN_FILE" 2>/dev/null; then
  echo "Circuit breaker: allowing repeat-blocked task (same subject blocked before)" >&2
  exit 0
fi
# Record this subject as blocked
echo "$SUBJECT_HASH" >> "$SEEN_FILE" 2>/dev/null || true
exit 2
