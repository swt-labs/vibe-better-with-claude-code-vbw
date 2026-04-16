#!/bin/bash
set -u
# skill-decision-logger.sh — PreToolUse logger for skill evaluation decisions
#
# Parses the subagent prompt from the PreToolUse hook input for
# <skill_activation> or <skill_no_activation> blocks, and appends
# a one-line JSON entry to .vbw-planning/.skill-decisions.log.
#
# Always exits 0 — fail-open, never blocks agent spawn.

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

INPUT=$(cat 2>/dev/null) || exit 0
[ -z "$INPUT" ] && exit 0

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P 2>/dev/null) || exit 0
[ -f "$SCRIPT_DIR/lib/vbw-config-root.sh" ] || exit 0
# shellcheck source=scripts/lib/vbw-config-root.sh
. "$SCRIPT_DIR/lib/vbw-config-root.sh" || exit 0

find_vbw_root >/dev/null 2>&1 || exit 0
LOG_DIR="${VBW_PLANNING_DIR:-}"
[ -n "$LOG_DIR" ] || exit 0
LOG_FILE="$LOG_DIR/.skill-decisions.log"

# Extract the prompt from the tool input — try .tool_input.prompt first,
# then .tool_input.description (TaskCreate uses prompt, Agent uses description)
# Use array filter to skip null and empty strings
PROMPT=$(echo "$INPUT" | jq -r '[.tool_input.prompt, .tool_input.description] | map(select(. != null and . != "")) | first // ""' 2>/dev/null) || exit 0
[ -z "$PROMPT" ] && exit 0

# Extract agent name from tool input (try agent, name, then subagent_type)
# Use array filter to skip null and empty strings
AGENT_NAME=$(echo "$INPUT" | jq -r '[.tool_input.agent, .tool_input.name, .tool_input.subagent_type] | map(select(. != null and . != "")) | first // "unknown"' 2>/dev/null) || AGENT_NAME="unknown"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null) || TIMESTAMP="unknown"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"

# Detect which skill block is present
DECISION=""
REASON=""

# Extract content between XML-style tags, handling multi-line blocks
extract_tag_content() {
  local tag="$1"
  local open_tag="<${tag}>"
  local close_tag="</${tag}>"
  local collecting=false
  local result=""
  while IFS= read -r line; do
    if [ "$collecting" = true ]; then
      case "$line" in
        *"$close_tag"*)
          local before="${line%%"$close_tag"*}"
          [ -n "$before" ] && result="${result} ${before}"
          break
          ;;
        *)
          result="${result} ${line}"
          ;;
      esac
    else
      case "$line" in
        *"$open_tag"*)
          collecting=true
          local after="${line#*"$open_tag"}"
          case "$after" in
            *"$close_tag"*)
              # Single-line case: both open and close on same line
              result="${after%%"$close_tag"*}"
              break
              ;;
            *)
              [ -n "$after" ] && result="$after"
              ;;
          esac
          ;;
      esac
    fi
  done <<< "$PROMPT"
  # Collapse internal whitespace and trim leading/trailing
  result=$(printf '%s' "$result" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')
  printf '%s' "$result"
}

if printf '%s' "$PROMPT" | grep -q '<skill_activation>'; then
  DECISION="activation"
  REASON=$(extract_tag_content "skill_activation")
elif printf '%s' "$PROMPT" | grep -q '<skill_no_activation>'; then
  DECISION="no_activation"
  REASON=$(extract_tag_content "skill_no_activation")
fi

# Only log if a skill decision block was found
[ -z "$DECISION" ] && exit 0

# Truncate reason to avoid oversized log entries
if [ "${#REASON}" -gt 200 ]; then
  REASON="${REASON:0:200}..."
fi

# Write one-line JSON entry
jq -n -c \
  --arg ts "$TIMESTAMP" \
  --arg session "$SESSION_ID" \
  --arg agent "$AGENT_NAME" \
  --arg decision "$DECISION" \
  --arg reason "$REASON" \
  '{ts: $ts, session: $session, agent: $agent, decision: $decision, reason: $reason}' \
  >> "$LOG_FILE" 2>/dev/null

exit 0
