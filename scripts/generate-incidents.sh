#!/usr/bin/env bash
set -u

# generate-incidents.sh <phase-number>
# Auto-generates {phase}-INCIDENTS.md from task_blocked and task_completion_rejected events.
# Output: path to generated file, or empty if no incidents found.
# Exit: 0 always — incident generation must never block execution.

PHASE="${1:-}"

if [ -z "$PHASE" ]; then
  echo "Usage: generate-incidents.sh <phase-number>" >&2
  exit 0
fi

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
EVENTS_FILE="${PLANNING_DIR}/.events/event-log.jsonl"
PHASES_DIR="${PLANNING_DIR}/phases"

# Check event log exists
if [ ! -f "$EVENTS_FILE" ]; then
  exit 0
fi

# Find phase directory
PADDED=$(printf "%02d" "$PHASE" 2>/dev/null || echo "$PHASE")
PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PADDED}-*" 2>/dev/null | head -1)
if [ -z "$PHASE_DIR" ]; then
  PHASE_DIR=$(find "$PHASES_DIR" -maxdepth 1 -type d -name "${PHASE}-*" 2>/dev/null | head -1)
fi
if [ -z "$PHASE_DIR" ]; then
  exit 0
fi

# Extract incidents for this phase
BLOCKED=$(jq -s --argjson p "$PHASE" '[.[] | select(.event == "task_blocked" and .phase == $p)]' "$EVENTS_FILE" 2>/dev/null || echo "[]")
REJECTED=$(jq -s --argjson p "$PHASE" '[.[] | select(.event == "task_completion_rejected" and .phase == $p)]' "$EVENTS_FILE" 2>/dev/null || echo "[]")

BLOCKED_COUNT=$(echo "$BLOCKED" | jq 'length' 2>/dev/null || echo "0")
REJECTED_COUNT=$(echo "$REJECTED" | jq 'length' 2>/dev/null || echo "0")
TOTAL=$((BLOCKED_COUNT + REJECTED_COUNT))

if [ "$TOTAL" -eq 0 ]; then
  exit 0
fi

INCIDENTS_FILE="${PHASE_DIR}/${PADDED}-INCIDENTS.md"

{
  echo "# Phase ${PHASE} Incidents"
  echo ""
  echo "Auto-generated from event log. Total: ${TOTAL} incidents."
  echo ""
  echo "## Blockers (${BLOCKED_COUNT})"
  echo ""
  if [ "$BLOCKED_COUNT" -gt 0 ]; then
    echo "| Time | Task | Reason | Next Action |"
    echo "|------|------|--------|-------------|"
    echo "$BLOCKED" | jq -r '.[] | "| \(.ts) | \(.data.task_id // "unknown") | \(.data.reason // .data.evidence // "unspecified") | \(.data.next_action // "none") |"' 2>/dev/null || true
  else
    echo "No blockers recorded."
  fi
  echo ""
  echo "## Rejections (${REJECTED_COUNT})"
  echo ""
  if [ "$REJECTED_COUNT" -gt 0 ]; then
    echo "| Time | Task | Reason |"
    echo "|------|------|--------|"
    echo "$REJECTED" | jq -r '.[] | "| \(.ts) | \(.data.task_id // "unknown") | \(.data.reason // .data.evidence // "unspecified") |"' 2>/dev/null || true
  else
    echo "No rejections recorded."
  fi
} > "$INCIDENTS_FILE" 2>/dev/null || exit 0

echo "$INCIDENTS_FILE"
