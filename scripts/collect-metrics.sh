#!/usr/bin/env bash
set -u

# collect-metrics.sh <event> <phase> [plan] [key=value ...]
# Appends a JSON line to .vbw-planning/.metrics/run-metrics.jsonl
# Events: cache_hit, cache_miss, compile_context, execute_task, execute_plan,
#         execute_phase_start, execute_phase_complete
# Exit 0 always — metrics must never block execution.

if [ $# -lt 2 ]; then
  echo "Usage: collect-metrics.sh <event> <phase> [plan] [key=value ...]" >&2
  exit 0
fi

EVENT="$1"
PHASE="$2"
shift 2

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"

# Check metrics flag — if disabled, exit silently
CONFIG_PATH="$PLANNING_DIR/config.json"
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  METRICS_ENABLED=$(jq -r 'if .metrics != null then .metrics elif .v3_metrics != null then .v3_metrics else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
  if [ "$METRICS_ENABLED" != "true" ]; then
    exit 0
  fi
fi

PLAN=""
DATA_PAIRS=""

# Parse remaining args: first non-key=value arg is plan number
for arg in "$@"; do
  case "$arg" in
    *=*)
      # key=value pair
      KEY=$(echo "$arg" | cut -d'=' -f1)
      VALUE=$(echo "$arg" | cut -d'=' -f2-)
      if [ -n "$DATA_PAIRS" ]; then
        DATA_PAIRS="${DATA_PAIRS},\"${KEY}\":\"${VALUE}\""
      else
        DATA_PAIRS="\"${KEY}\":\"${VALUE}\""
      fi
      ;;
    *)
      # Plan number
      if [ -z "$PLAN" ]; then
        PLAN="$arg"
      fi
      ;;
  esac
done

METRICS_DIR="$PLANNING_DIR/.metrics"
METRICS_FILE="${METRICS_DIR}/run-metrics.jsonl"

# Create dir if needed
mkdir -p "$METRICS_DIR" 2>/dev/null || { exit 0; }

# Build JSON line
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

PLAN_FIELD=""
if [ -n "$PLAN" ]; then
  PLAN_FIELD=",\"plan\":${PLAN}"
fi

DATA_FIELD=""
if [ -n "$DATA_PAIRS" ]; then
  DATA_FIELD=",\"data\":{${DATA_PAIRS}}"
fi

echo "{\"ts\":\"${TS}\",\"event\":\"${EVENT}\",\"phase\":${PHASE}${PLAN_FIELD}${DATA_FIELD}}" >> "$METRICS_FILE" 2>/dev/null || true
