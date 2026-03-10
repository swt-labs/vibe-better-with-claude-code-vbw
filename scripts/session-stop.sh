#!/bin/bash
set -u
# Stop hook: Log session metrics to .vbw-planning/.session-log.jsonl
# Non-blocking, fail-open (always exit 0)

PLANNING_DIR=".vbw-planning"

# Guard: only log if planning directory exists
if [ ! -d "$PLANNING_DIR" ]; then
  exit 0
fi

INPUT=$(cat)

# Extract session metrics via jq (fail-silent on missing fields)
COST=$(echo "$INPUT" | jq -r '.cost_usd // .cost // 0' 2>/dev/null)
DURATION=$(echo "$INPUT" | jq -r '.duration_ms // .duration // 0' 2>/dev/null)
TOKENS_IN=$(echo "$INPUT" | jq -r '.tokens_in // .input_tokens // 0' 2>/dev/null)
TOKENS_OUT=$(echo "$INPUT" | jq -r '.tokens_out // .output_tokens // 0' 2>/dev/null)
MODEL=$(echo "$INPUT" | jq -r '.model // "unknown"' 2>/dev/null)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append JSON line to session log (atomic: write to temp file, then append)
TEMP_FILE="$PLANNING_DIR/.session-log.jsonl.tmp"

jq -n \
  --arg ts "$TIMESTAMP" \
  --argjson dur "${DURATION:-0}" \
  --argjson cost "${COST:-0}" \
  --argjson tin "${TOKENS_IN:-0}" \
  --argjson tout "${TOKENS_OUT:-0}" \
  --arg model "$MODEL" \
  --arg branch "$BRANCH" \
  '{timestamp: $ts, duration_ms: $dur, cost_usd: $cost, tokens_in: $tin, tokens_out: $tout, model: $model, branch: $branch}' \
  > "$TEMP_FILE" 2>/dev/null \
  && [ -O "$TEMP_FILE" ] \
  && cat "$TEMP_FILE" >> "$PLANNING_DIR/.session-log.jsonl" 2>/dev/null

rm -f "$TEMP_FILE" 2>/dev/null

# Persist cost summary from agent-attributed ledger (if it exists)
if [ -f "$PLANNING_DIR/.cost-ledger.json" ]; then
  COST_DATA=$(cat "$PLANNING_DIR/.cost-ledger.json" 2>/dev/null)
  if [ -n "$COST_DATA" ] && echo "$COST_DATA" | jq empty 2>/dev/null; then
    jq -n --arg ts "$TIMESTAMP" --argjson costs "$COST_DATA" \
      '{timestamp: $ts, type: "cost_summary", costs: $costs}' \
      >> "$PLANNING_DIR/.session-log.jsonl" 2>/dev/null
  fi
  rm -f "$PLANNING_DIR/.cost-ledger.json" 2>/dev/null
fi

# Clean up transient agent markers and stale lock dir.
# Keep .vbw-session so plain-text follow-ups in an active VBW flow remain
# unblocked across assistant turns. .vbw-session is cleared by explicit
# non-VBW slash commands in prompt-preflight.sh (and stale markers are ignored
# by security-filter.sh after 24h).
rmdir "$PLANNING_DIR/.active-agent-count.lock" 2>/dev/null || true
rm -f "$PLANNING_DIR/.active-agent" "$PLANNING_DIR/.active-agent-count" "$PLANNING_DIR/.agent-panes" "$PLANNING_DIR/.task-verify-seen" "$PLANNING_DIR/.delegated-workflow.json" 2>/dev/null

# Clean up stale worktrees (>2 hours) — fail-silent
SCRIPT_DIR_STOP="$(cd "$(dirname "$0")" && pwd)"
WORKTREES_DIR="$(pwd)/.vbw-worktrees"
if [ -d "$WORKTREES_DIR" ] && [ -f "$SCRIPT_DIR_STOP/worktree-cleanup.sh" ]; then
  NOW_STOP=$(date +%s)
  STALE_SECS=7200
  for wt_dir in "$WORKTREES_DIR"/*/; do
    [ ! -d "$wt_dir" ] && continue
    if [[ "$OSTYPE" == "darwin"* ]]; then
      WT_MTIME=$(stat -f %m "$wt_dir" 2>/dev/null) || WT_MTIME=0
    else
      WT_MTIME=$(stat -c %Y "$wt_dir" 2>/dev/null) || WT_MTIME=0
    fi
    WT_AGE=$((NOW_STOP - WT_MTIME))
    if [ "$WT_AGE" -gt "$STALE_SECS" ]; then
      WT_NAME=$(basename "$wt_dir")
      # Parse phase and plan from directory name (format: {phase}-{plan})
      WT_PHASE=$(echo "$WT_NAME" | cut -d'-' -f1)
      WT_PLAN=$(echo "$WT_NAME" | cut -d'-' -f2)
      bash "$SCRIPT_DIR_STOP/worktree-cleanup.sh" "$WT_PHASE" "$WT_PLAN" 2>/dev/null || true
    fi
  done
fi

exit 0
