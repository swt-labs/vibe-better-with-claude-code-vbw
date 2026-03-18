#!/usr/bin/env bash
set -u

# recover-state.sh <phase> [phases-dir]
# Rebuild .execution-state.json from event log + SUMMARY.md files.
# Reads event-log.jsonl for phase_start/plan_end events, cross-references
# with SUMMARY.md files to reconstruct plan statuses.
# Output: reconstructed execution state JSON to stdout.
# Fail-open: exit 0 always. On error, outputs empty object.

# Source shared summary-status helpers for status-aware SUMMARY detection
_RS_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$_RS_SCRIPT_DIR/summary-utils.sh" ]; then
  # shellcheck source=summary-utils.sh
  . "$_RS_SCRIPT_DIR/summary-utils.sh"
  # Bridge wrappers: recover-state.sh call sites use these names
  is_plan_finalized() { is_summary_terminal "$1"; }
  extract_summary_status() {
    local f="$1"
    [ -f "$f" ] || return 1
    sed -n '/^---$/,/^---$/{ /^status:/{ s/^status:[[:space:]]*//; s/["'"'"']//g; p; }; }' "$f" 2>/dev/null | head -1 | tr -d '[:space:]'
  }
else
  # Safe default: treat plans as not finalized when helpers unavailable
  is_plan_finalized() { return 1; }
  extract_summary_status() { echo ""; return 1; }
fi

if [ $# -lt 1 ]; then
  echo "{}"
  exit 0
fi

PHASE="$1"

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
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

# Find latest valid plan_end status for a phase/plan pair.
# Uses jq fromjson? so malformed trailing lines do not mask earlier valid events.
latest_plan_event_status() {
  _events_file="$1"
  _phase="$2"
  _plan="$3"
  jq -Rr \
    --argjson phase "$_phase" \
    --argjson plan "$_plan" \
    '
      fromjson?
      | select(.event == "plan_end")
      | select((((.phase | tostring | tonumber?) // -1) == $phase))
      | select((((.plan  | tostring | tonumber?) // -1) == $plan))
      | (.data.status // empty)
    ' "$_events_file" 2>/dev/null | tail -n 1
}

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

  # Check if SUMMARY.md exists with terminal status
  SUMMARY_FILE="$PHASE_DIR/${PLAN_ID}-SUMMARY.md"
  if is_plan_finalized "$SUMMARY_FILE"; then
    PLAN_STATUS=$(extract_summary_status "$SUMMARY_FILE")
    # Normalize to execution-state compatible values
    case "$PLAN_STATUS" in
      complete|completed) PLAN_STATUS="complete" ;;
      partial) PLAN_STATUS="partial" ;;
      failed) PLAN_STATUS="failed" ;;
      *) PLAN_STATUS="pending" ;;
    esac
  else
    PLAN_STATUS="pending"
  fi

  # Check event log for plan_end events.
  # Policy: latest valid event is authoritative over SUMMARY.md, which may be stale.
  if [ -f "$EVENTS_FILE" ]; then
    # Strip leading zeros — log-event.sh writes bare integers ("plan":1 not "plan":01)
    PLAN_NUM=$(echo "$PLAN_ID" | sed 's/^[0-9]*-//' | sed 's/^0*//')
    [ -z "$PLAN_NUM" ] && PLAN_NUM="0"
    EVENT_STATUS=$(latest_plan_event_status "$EVENTS_FILE" "$PHASE" "$PLAN_NUM") || EVENT_STATUS=""
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
