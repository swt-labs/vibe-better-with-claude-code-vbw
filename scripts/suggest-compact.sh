#!/bin/bash
set -u
# suggest-compact.sh — Pre-flight context guard for heavy commands.
#
# Reads cached context window usage (from statusline) and estimated token cost
# for the requested mode. If remaining context is insufficient, emits a warning
# that the command template injects into the prompt.
#
# Usage: bash suggest-compact.sh <mode>
#   mode: execute|plan|verify|qa|discuss
#
# Reads:
#   .vbw-planning/.context-usage   — "used_pct|context_window_size" (cached by statusline)
#   .vbw-planning/config.json      — compaction_threshold (optional)
#
# Output (stdout):
#   Empty string if context is fine, or a warning block if near capacity.

MODE="${1:-execute}"

PLANNING_DIR=".vbw-planning"
USAGE_FILE="$PLANNING_DIR/.context-usage"

# Read autonomy from config
AUTONOMY="standard"
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  AUTONOMY=$(jq -r '.autonomy // "standard"' "$PLANNING_DIR/config.json" 2>/dev/null) || AUTONOMY="standard"
fi

# Estimated token cost per mode (conservative upper bounds from code review)
case "$MODE" in
  execute)  EST_COST=25000 ;;
  plan)     EST_COST=12000 ;;
  verify)   EST_COST=10000 ;;
  qa)       EST_COST=8000  ;;
  discuss)  EST_COST=6000  ;;
  *)        EST_COST=10000 ;;
esac

# Read cached context usage from statusline
if [ ! -f "$USAGE_FILE" ]; then
  # No cached data yet (first command in session) — can't guard, skip silently
  exit 0
fi

IFS='|' read -r USED_PCT CTX_SIZE < "$USAGE_FILE" 2>/dev/null || exit 0

# Validate
if ! [[ "${USED_PCT:-}" =~ ^[0-9]+$ ]] || ! [[ "${CTX_SIZE:-}" =~ ^[0-9]+$ ]]; then
  exit 0
fi

[ "$CTX_SIZE" -eq 0 ] && exit 0

# Calculate remaining tokens
REMAINING=$(( CTX_SIZE * (100 - USED_PCT) / 100 ))

# Read compaction_threshold from config if available (override safety margin)
THRESHOLD=""
if [ -f "$PLANNING_DIR/config.json" ] && command -v jq &>/dev/null; then
  THRESHOLD=$(jq -r '.compaction_threshold // empty' "$PLANNING_DIR/config.json" 2>/dev/null)
fi

# Determine the warning threshold: remaining must exceed estimated cost + buffer.
# Buffer = 15% of estimated cost (allow room for the workflow to breathe).
NEEDED=$(( EST_COST + EST_COST * 15 / 100 ))

# If compaction_threshold is set, also check: used tokens must stay below it after load.
USED_TOKENS=$(( CTX_SIZE * USED_PCT / 100 ))
THRESHOLD_EXCEEDED=false
if [[ "${THRESHOLD:-}" =~ ^[0-9]+$ ]] && [ "$THRESHOLD" -gt 0 ]; then
  PROJECTED=$(( USED_TOKENS + EST_COST ))
  if [ "$PROJECTED" -gt "$THRESHOLD" ]; then
    THRESHOLD_EXCEEDED=true
  fi
fi

if [ "$REMAINING" -lt "$NEEDED" ] || [ "$THRESHOLD_EXCEEDED" = true ]; then
  # Emit warning
  if [ "$AUTONOMY" = "confident" ] || [ "$AUTONOMY" = "pure-vibe" ]; then
    cat <<EOF
⚠ **PRE-FLIGHT CONTEXT GUARD:** Context window is at ${USED_PCT}% (${REMAINING} tokens remaining). This ${MODE} workflow needs ~${EST_COST} tokens of headroom. Running /compact now to prevent mid-workflow compaction.

**ACTION REQUIRED:** Run /compact before proceeding with this workflow. Auto-compacting now because autonomy is set to ${AUTONOMY}.
EOF
  else
    cat <<EOF
⚠ **PRE-FLIGHT CONTEXT GUARD:** Context window is at ${USED_PCT}% (~${REMAINING} tokens remaining). This ${MODE} workflow needs ~${EST_COST} tokens of headroom. Starting now risks mid-workflow auto-compaction, which degrades context quality.

**RECOMMENDED:** Run \`/compact\` first, then re-run this command. Or run \`/vbw:pause\` then \`/vbw:resume\` for a clean context reload.
EOF
  fi
fi

exit 0
