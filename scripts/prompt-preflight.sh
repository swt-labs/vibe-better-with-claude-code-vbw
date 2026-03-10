#!/bin/bash
set -u
# UserPromptSubmit: Pre-flight validation for VBW commands (non-blocking, exit 0)

PLANNING_DIR=".vbw-planning"
[ -d "$PLANNING_DIR" ] || exit 0

INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // .content // ""' 2>/dev/null)
[ -z "$PROMPT" ] && exit 0

is_expanded_vbw_prompt() {
  local prompt="$1"
  local frontmatter

  # Require YAML frontmatter at the top of the prompt (first non-empty line is ---)
  if ! printf '%s\n' "$prompt" | awk '
    BEGIN { saw = 0 }
    /^[[:space:]]*$/ { next }
    {
      saw = 1
      if ($0 ~ /^[[:space:]]*---[[:space:]]*$/) {
        exit 0
      }
      exit 1
    }
    END {
      if (!saw) {
        exit 1
      }
    }
  '; then
    return 1
  fi

  frontmatter=$(printf '%s\n' "$prompt" | awk '
    BEGIN { in_frontmatter = 0 }
    /^[[:space:]]*---[[:space:]]*$/ {
      if (in_frontmatter == 0) {
        in_frontmatter = 1
        next
      }
      if (in_frontmatter == 1) {
        exit
      }
    }
    in_frontmatter == 1 { print }
  ')

  [ -n "$frontmatter" ] && printf '%s\n' "$frontmatter" | grep -qiE '^[[:space:]]*name:[[:space:]]*vbw:'
}

is_archive_vibe_prompt() {
  local prompt="$1"

  # Raw slash command shape
  if printf '%s\n' "$prompt" | grep -qiE '/vbw:vibe[^[:cntrl:]]*--archive'; then
    return 0
  fi

  # Expanded command shape (frontmatter name: vbw:*)
  # If this expanded prompt includes --archive, treat it as an archive intent.
  if is_expanded_vbw_prompt "$prompt" && printf '%s\n' "$prompt" | grep -qi -- '--archive'; then
    return 0
  fi

  return 1
}

# VBW context marker: signal statusline that VBW context is active in this session.
# Created on any VBW command; cleared by session-start.sh (new session) and
# post-compact.sh (compaction degrades context reliability).
if echo "$PROMPT" | grep -qi '^/vbw:' || is_expanded_vbw_prompt "$PROMPT"; then
  echo "1" > "$PLANNING_DIR/.vbw-context" 2>/dev/null || true
fi

# GSD Isolation: create .vbw-session marker on VBW command invocation.
# Detection covers raw slash commands (/vbw:*) and expanded command content
# (YAML frontmatter with "name: vbw:").
# Only CREATE the marker here; removal is handled by session-stop.sh at session end.
# Deleting on non-/vbw: prompts caused false blocks mid-workflow when users send
# follow-up messages (plan approvals, answers) that don't start with /vbw:.
if [ -f "$PLANNING_DIR/.gsd-isolation" ]; then
  if echo "$PROMPT" | grep -qi '^/vbw:'; then
    echo "session" > "$PLANNING_DIR/.vbw-session"
  elif is_expanded_vbw_prompt "$PROMPT"; then
    echo "session" > "$PLANNING_DIR/.vbw-session"
  fi
  # Plain text prompts: leave marker unchanged (continuation of active flow)
fi

WARNING=""
BLOCK_MSG=""

# Check: /vbw:vibe --execute when no PLAN.md exists
if echo "$PROMPT" | grep -q '/vbw:vibe.*--execute'; then
  CURRENT_PHASE=""
  if [ -f "$PLANNING_DIR/STATE.md" ]; then
    CURRENT_PHASE=$(grep -m1 "^## Current Phase" "$PLANNING_DIR/STATE.md" | sed 's/.*Phase[: ]*//' | tr -d ' ')
  fi

  if [ -n "$CURRENT_PHASE" ]; then
    PHASE_DIR="$PLANNING_DIR/phases/$CURRENT_PHASE"
    PLAN_COUNT=$(find "$PHASE_DIR" -name "PLAN.md" -o -name "*-PLAN.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PLAN_COUNT" -eq 0 ]; then
      WARNING="No PLAN.md for phase $CURRENT_PHASE. Run /vbw:vibe to plan first."
    fi
  fi
fi

# Check: /vbw:vibe --archive with incomplete phases
if is_archive_vibe_prompt "$PROMPT"; then
  # Hard gate: unresolved UAT (active or milestone) blocks archive requests,
  # including bypass attempts like --skip-audit / --force.
  GUARD_SCRIPT="$(dirname "$0")/archive-uat-guard.sh"
  if [ -f "$GUARD_SCRIPT" ]; then
    GUARD_OUTPUT=$(bash "$GUARD_SCRIPT" 2>/dev/null)
    GUARD_RC=$?
    if [ "$GUARD_RC" -eq 2 ]; then
      BLOCK_MSG="${GUARD_OUTPUT:-Archive blocked: unresolved UAT issues must be remediated before archiving.}"
    fi
  else
    WARNING="UAT guard script not found; archive safety check skipped."
  fi

  if [ -f "$PLANNING_DIR/STATE.md" ]; then
    INCOMPLETE=$(grep -c "status:.*incomplete\|status:.*in.progress\|status:.*pending" "$PLANNING_DIR/STATE.md" 2>/dev/null || echo 0)
    if [ "$INCOMPLETE" -gt 0 ]; then
      if [ -n "$WARNING" ]; then
        WARNING="$WARNING $INCOMPLETE incomplete phase(s). Review STATE.md before shipping."
      else
        WARNING="$INCOMPLETE incomplete phase(s). Review STATE.md before shipping."
      fi
    fi
  fi
fi

if [ -n "$BLOCK_MSG" ]; then
  jq -n --arg msg "$BLOCK_MSG" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": ("VBW pre-flight block: " + $msg)
    }
  }'
  exit 2
fi

if [ -n "$WARNING" ]; then
  jq -n --arg msg "$WARNING" '{
    "hookSpecificOutput": {
      "hookEventName": "UserPromptSubmit",
      "additionalContext": ("VBW pre-flight warning: " + $msg)
    }
  }'
fi

exit 0
