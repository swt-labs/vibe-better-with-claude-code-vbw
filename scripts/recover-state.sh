#!/usr/bin/env bash
set -u

# recover-state.sh <phase> [phases-dir]
# Rebuild .execution-state.json from event log + SUMMARY.md files.
# Reads event-log.jsonl for phase_start/plan_end events, cross-references
# with SUMMARY.md files to reconstruct plan statuses.
# Output: reconstructed execution state JSON to stdout.
# Fail-open: exit 0 always. On error, outputs empty object.

if [ $# -lt 1 ]; then
  echo "{}"
  exit 0
fi

PHASE="$1"

PLANNING_DIR=".vbw-planning"
CONFIG_PATH="${PLANNING_DIR}/config.json"
EVENTS_FILE="${PLANNING_DIR}/.events/event-log.jsonl"

# Check event_recovery flag — if disabled, output empty object
# Legacy fallback: honor v3_event_recovery if unprefixed key missing (pre-migration brownfield)
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  EVENT_RECOVERY=$(jq -r 'if .event_recovery != null then .event_recovery elif .v3_event_recovery != null then .v3_event_recovery else false end' "$CONFIG_PATH" 2>/dev/null || echo "false")
  if [ "$EVENT_RECOVERY" != "true" ]; then
    echo "{}"
    exit 0
  fi
fi

# Need jq for JSON processing
command -v jq &>/dev/null || { echo "{}"; exit 0; }

# Find phase directory
PHASES_DIR="${2:-${PLANNING_DIR}/phases}"
PHASE_DIR=""
for d in "$PHASES_DIR"/"$(printf '%02d' "$PHASE")"-*/; do
  [ -d "$d" ] && PHASE_DIR="$d" && break
done

[ -z "$PHASE_DIR" ] && { echo "{}"; exit 0; }

PHASE_SLUG=$(basename "$PHASE_DIR" | sed "s/^$(printf '%02d' "$PHASE")-//")

# Collect plan IDs from PLAN.md files
PLANS_JSON="[]"
for plan_file in "$PHASE_DIR"/*-PLAN.md; do
  [ ! -f "$plan_file" ] && continue
  PLAN_ID=$(basename "$plan_file" | sed 's/-PLAN\.md$//')
  PLAN_TITLE=$(awk '/^title:/ {gsub(/^title: *"?|"?$/, ""); print}' "$plan_file" 2>/dev/null) || PLAN_TITLE="unknown"
  PLAN_WAVE=$(awk '/^wave:/ {gsub(/^wave: */, ""); print}' "$plan_file" 2>/dev/null) || PLAN_WAVE="1"

  # Check if SUMMARY.md exists
  SUMMARY_FILE="$PHASE_DIR/${PLAN_ID}-SUMMARY.md"
  if [ -f "$SUMMARY_FILE" ]; then
    PLAN_STATUS="complete"
  else
    PLAN_STATUS="pending"
  fi

  # Check event log for plan_end events
  if [ -f "$EVENTS_FILE" ] && [ "$PLAN_STATUS" = "pending" ]; then
    # Strip leading zeros — log-event.sh writes bare integers ("plan":1 not "plan":01)
    PLAN_NUM=$(echo "$PLAN_ID" | sed 's/^[0-9]*-//' | sed 's/^0*//')
    [ -z "$PLAN_NUM" ] && PLAN_NUM="0"
    EVENT_STATUS=$(grep "\"plan_end\"" "$EVENTS_FILE" 2>/dev/null | \
      grep "\"phase\":${PHASE}" 2>/dev/null | \
      grep "\"plan\":${PLAN_NUM}" 2>/dev/null | \
      tail -1 | jq -r '.data.status // "unknown"' 2>/dev/null) || EVENT_STATUS=""
    [ "$EVENT_STATUS" = "complete" ] && PLAN_STATUS="complete"
    [ "$EVENT_STATUS" = "failed" ] && PLAN_STATUS="failed"
  fi

  # Validate wave is numeric; default to 1 if empty or non-numeric
  case "${PLAN_WAVE:-1}" in
    ''|*[!0-9]*) PLAN_WAVE=1 ;;
  esac

  PLANS_JSON=$(echo "$PLANS_JSON" | jq \
    --arg id "$PLAN_ID" \
    --arg title "$PLAN_TITLE" \
    --argjson wave "${PLAN_WAVE:-1}" \
    --arg status "$PLAN_STATUS" \
    '. + [{"id": $id, "title": $title, "wave": $wave, "status": $status}]' 2>/dev/null) || continue
done

# Determine overall status
TOTAL=$(echo "$PLANS_JSON" | jq 'length' 2>/dev/null) || TOTAL=0
COMPLETE=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "complete")] | length' 2>/dev/null) || COMPLETE=0
FAILED=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "failed")] | length' 2>/dev/null) || FAILED=0

if [ "$COMPLETE" -eq "$TOTAL" ] && [ "$TOTAL" -gt 0 ]; then
  STATUS="complete"
elif [ "$FAILED" -gt 0 ]; then
  STATUS="failed"
elif [ "$COMPLETE" -gt 0 ]; then
  STATUS="running"
else
  STATUS="pending"
fi

# Determine current wave
MAX_WAVE=$(echo "$PLANS_JSON" | jq '[.[].wave] | max // 1' 2>/dev/null) || MAX_WAVE=1
CURRENT_WAVE=$(echo "$PLANS_JSON" | jq '[.[] | select(.status == "pending" or .status == "running") | .wave] | min // 1' 2>/dev/null) || CURRENT_WAVE=1

# Build result
jq -n \
  --argjson phase "$PHASE" \
  --arg phase_name "$PHASE_SLUG" \
  --arg status "$STATUS" \
  --argjson wave "$CURRENT_WAVE" \
  --argjson total_waves "$MAX_WAVE" \
  --argjson plans "$PLANS_JSON" \
  '{phase: $phase, phase_name: $phase_name, status: $status, wave: $wave, total_waves: $total_waves, plans: $plans}' \
  2>/dev/null || echo "{}"

exit 0
