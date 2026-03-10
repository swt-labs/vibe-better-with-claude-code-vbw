#!/bin/bash
set -u
# PreCompact hook: Inject VBW-specific compaction priorities
#
# CC 2.1.47+ handles natively:
#   - Plan mode preservation
#   - Basic conversation flow retention
#
# VBW adds:
#   - Agent-specific codebase re-read instructions
#   - Execution state snapshots for crash recovery
#   - Compaction markers for Dev re-read guards

INPUT=$(cat)
AGENT_NAME=$(echo "$INPUT" | jq -r '.agent_name // .agentName // ""')
MATCHER=$(echo "$INPUT" | jq -r '.matcher // "auto"')

# VBW-specific compaction priorities per agent role
case "$AGENT_NAME" in
  *scout*)
    PRIORITIES="Preserve research findings, URLs, confidence assessments"
    ;;
  *dev*)
    PRIORITIES="Preserve commit hashes, file paths modified, deviation decisions, current task number. After compaction, if .vbw-planning/codebase/META.md exists, re-read CONVENTIONS.md, PATTERNS.md, STRUCTURE.md, and DEPENDENCIES.md (whichever exist) from .vbw-planning/codebase/"
    # Inject worktree path if agent has a mapping
    AGENT_NAME_SHORT=$(echo "$AGENT_NAME" | sed 's/.*vbw-//')
    WORKTREE_MAP_FILE=".vbw-planning/.agent-worktrees/${AGENT_NAME_SHORT}.json"
    if [ -f "$WORKTREE_MAP_FILE" ]; then
      WORKTREE_PATH=$(jq -r '.worktree_path // ""' "$WORKTREE_MAP_FILE" 2>/dev/null) || WORKTREE_PATH=""
      if [ -n "$WORKTREE_PATH" ]; then
        PRIORITIES="$PRIORITIES CRITICAL: Your working directory is ${WORKTREE_PATH}. All file operations MUST use this path."
      fi
    fi
    ;;
  *qa*)
    PRIORITIES="Preserve pass/fail status, gap descriptions, verification results. After compaction, if .vbw-planning/codebase/META.md exists, re-read TESTING.md, CONCERNS.md, and ARCHITECTURE.md (whichever exist) from .vbw-planning/codebase/"
    ;;
  *lead*)
    PRIORITIES="Preserve phase status, plan structure, coordination decisions. After compaction, if .vbw-planning/codebase/META.md exists, re-read ARCHITECTURE.md, CONCERNS.md, and STRUCTURE.md (whichever exist) from .vbw-planning/codebase/"
    ;;
  *architect*)
    PRIORITIES="Preserve requirement IDs, phase structure, success criteria, key decisions. After compaction, if .vbw-planning/codebase/META.md exists, re-read ARCHITECTURE.md and STACK.md (whichever exist) from .vbw-planning/codebase/"
    ;;
  *debugger*)
    PRIORITIES="Preserve reproduction steps, hypotheses, evidence gathered, diagnosis. After compaction, if .vbw-planning/codebase/META.md exists, re-read ARCHITECTURE.md, CONCERNS.md, PATTERNS.md, and DEPENDENCIES.md (whichever exist) from .vbw-planning/codebase/"
    ;;
  *)
    PRIORITIES="Preserve active command being executed, user's original request, current phase/plan context, file modification paths, any pending user decisions. Discard: tool output details, reference file contents (re-read from disk), previous command results"
    ;;
esac

# Inject shutdown protocol reminder for team agents (survives compaction).
# NOTE: Keep this reminder in sync with the Shutdown Handling section in agents/vbw-*.md.
case "$AGENT_NAME" in
  *scout*|*dev*|*qa*|*lead*|*debugger*|*docs*)
    PRIORITIES="$PRIORITIES. SHUTDOWN PROTOCOL: If you receive a message containing \"shutdown_request\", you MUST call the SendMessage tool with a JSON body: {\"type\": \"shutdown_response\", \"approved\": true, \"request_id\": \"<id from shutdown_request>\", \"final_status\": \"complete|idle|in_progress\"}. Use the final_status value that matches your current state. Plain text responses do NOT satisfy the shutdown protocol."
    ;;
esac

# Add compact trigger context
if [ "$MATCHER" = "manual" ]; then
  PRIORITIES="$PRIORITIES. User requested compaction."
else
  PRIORITIES="$PRIORITIES. This is an automatic compaction at context limit."
fi

# Write compaction marker for Dev re-read guard (REQ-14)
if [ -d ".vbw-planning" ]; then
  date +%s > .vbw-planning/.compaction-marker 2>/dev/null || true
fi

# Write per-agent compaction marker for stuck-compaction watchdog
# The tmux-watchdog polls these files and kills agents stuck > 5 minutes
if [ -d ".vbw-planning" ]; then
  COMPACT_PID="$PPID"
  # Walk parent chain to find a registered agent PID
  PANE_MAP=".vbw-planning/.agent-panes"
  COMPACT_PANE_ID=""
  if [ -f "$PANE_MAP" ]; then
    _cpid="$COMPACT_PID"
    while [ -n "$_cpid" ] && [ "$_cpid" != "0" ] && [ "$_cpid" != "1" ]; do
      COMPACT_PANE_ID=$(awk -v p="$_cpid" '$1 == p { print $2; exit }' "$PANE_MAP" 2>/dev/null)
      if [ -n "$COMPACT_PANE_ID" ]; then
        COMPACT_PID="$_cpid"  # Use the PID that matched in the pane map
        break
      fi
      _cpid=$(ps -o ppid= -p "$_cpid" 2>/dev/null | tr -d ' ')
    done
  fi
  mkdir -p ".vbw-planning/.compacting" 2>/dev/null || true
  COMPACT_TS=$(date +%s)
  jq -n \
    --arg pid "$COMPACT_PID" \
    --arg pane_id "$COMPACT_PANE_ID" \
    --arg agent "$AGENT_NAME" \
    --argjson ts "$COMPACT_TS" \
    '{pid: $pid, pane_id: $pane_id, agent_name: $agent, started_at: $ts}' \
    > ".vbw-planning/.compacting/${COMPACT_PID}.json" 2>/dev/null || true
fi

# --- Compaction loop breaker (infinite-loop prevention) ---
# Increment a per-session counter. If it exceeds the threshold, inject a hard
# stop directive so the agent terminates instead of looping forever.
COMPACTION_LIMIT=10
COMPACTION_COUNT_FILE=".vbw-planning/.compaction-count"
if [ -d ".vbw-planning" ]; then
  PREV_COUNT=0
  if [ -f "$COMPACTION_COUNT_FILE" ]; then
    PREV_COUNT=$(cat "$COMPACTION_COUNT_FILE" 2>/dev/null | tr -dc '0-9')
    [ -z "$PREV_COUNT" ] && PREV_COUNT=0
  fi
  NEW_COUNT=$((PREV_COUNT + 1))
  echo "$NEW_COUNT" > "$COMPACTION_COUNT_FILE" 2>/dev/null || true

  if [ "$NEW_COUNT" -ge "$COMPACTION_LIMIT" ]; then
    PRIORITIES="CRITICAL — COMPACTION LOOP DETECTED (${NEW_COUNT} compactions). You are in an infinite auto-compaction loop: your non-reducible context exceeds the compaction threshold, so every tool call triggers another compaction with zero forward progress. STOP ALL WORK IMMEDIATELY. Do NOT read any more files. Do NOT call any tools. Report to the user: 'VBW compaction loop detected after ${NEW_COUNT} cycles — session context is too large for the effective context window. Kill this session and retry with a smaller task scope or increase context window.' Then terminate."
  elif [ "$NEW_COUNT" -ge 3 ]; then
    PRIORITIES="WARNING: This session has compacted ${NEW_COUNT} times (limit: ${COMPACTION_LIMIT}). You may be approaching an infinite compaction loop. Minimize file reads — only read files essential to your current task. $PRIORITIES"
  fi
fi

# --- Save agent state snapshot ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f ".vbw-planning/.execution-state.json" ] && [ -f "$SCRIPT_DIR/snapshot-resume.sh" ]; then
  SNAP_PHASE=$(jq -r '.phase // ""' ".vbw-planning/.execution-state.json" 2>/dev/null)
  if [ -n "$SNAP_PHASE" ]; then
    bash "$SCRIPT_DIR/snapshot-resume.sh" save "$SNAP_PHASE" ".vbw-planning/.execution-state.json" "$AGENT_NAME" "$MATCHER" 2>/dev/null || true
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%d %H:%M:%S")
    echo "[$TIMESTAMP] Snapshot saved: phase=$SNAP_PHASE agent=$AGENT_NAME" >> ".vbw-planning/.hook-errors.log" 2>/dev/null || true
  fi
fi

jq -n --arg ctx "$PRIORITIES" '{
  "hookEventName": "PreCompact",
  "hookSpecificOutput": {
    "hookEventName": "PreCompact",
    "additionalContext": ("Compaction priorities: " + $ctx + " Re-read assigned files from disk after compaction.")
  }
}'

exit 0
