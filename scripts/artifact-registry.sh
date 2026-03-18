#!/usr/bin/env bash
set -u

# artifact-registry.sh <command> [args...]
# Commands:
#   register <path> <event_id> [phase] [plan]  -- register artifact with auto-checksum
#   query <path>                                -- query artifact by path
#   list [phase]                                -- list all artifacts (optionally filter by phase)
# Stores in .vbw-planning/.artifacts/registry.jsonl
# Gated by two_phase_completion flag

PLANNING_DIR="${VBW_PLANNING_DIR:-.vbw-planning}"
CONFIG_PATH="${PLANNING_DIR}/config.json"

# Check feature flag
ENABLED=false
if [ -f "$CONFIG_PATH" ] && command -v jq &>/dev/null; then
  ENABLED=$(jq -r 'if .two_phase_completion != null then .two_phase_completion elif .v2_two_phase_completion != null then .v2_two_phase_completion else true end' "$CONFIG_PATH" 2>/dev/null || echo "true")
fi

if [ "$ENABLED" != "true" ]; then
  echo '{"result":"skipped","reason":"two_phase_completion=false"}'
  exit 0
fi

if [ $# -lt 1 ]; then
  echo '{"result":"error","errors":["usage: artifact-registry.sh <register|query|list> [args...]"]}'
  exit 0
fi

COMMAND="$1"
shift

ARTIFACTS_DIR="${PLANNING_DIR}/.artifacts"
REGISTRY_FILE="${ARTIFACTS_DIR}/registry.jsonl"

case "$COMMAND" in
  register)
    if [ $# -lt 2 ]; then
      echo '{"result":"error","errors":["usage: register <path> <event_id> [phase] [plan]"]}'
      exit 0
    fi
    ARTIFACT_PATH="$1"
    EVENT_ID="$2"
    PHASE="${3:-0}"
    PLAN="${4:-0}"

    mkdir -p "$ARTIFACTS_DIR" 2>/dev/null || exit 0

    # Compute checksum
    CHECKSUM=""
    if [ -f "$ARTIFACT_PATH" ]; then
      CHECKSUM=$(shasum -a 256 "$ARTIFACT_PATH" 2>/dev/null | cut -d' ' -f1 || echo "")
    fi

    TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")

    jq -n \
      --arg path "$ARTIFACT_PATH" \
      --arg checksum "$CHECKSUM" \
      --arg event_id "$EVENT_ID" \
      --argjson phase "$PHASE" \
      --argjson plan "$PLAN" \
      --arg ts "$TS" \
      '{path: $path, checksum: $checksum, event_id: $event_id, phase: $phase, plan: $plan, registered_at: $ts}' \
      >> "$REGISTRY_FILE" 2>/dev/null

    echo "{\"result\":\"registered\",\"path\":\"${ARTIFACT_PATH}\",\"checksum\":\"${CHECKSUM}\"}"
    ;;

  query)
    if [ $# -lt 1 ]; then
      echo '{"result":"error","errors":["usage: query <path>"]}'
      exit 0
    fi
    QUERY_PATH="$1"

    if [ ! -f "$REGISTRY_FILE" ]; then
      echo '{"result":"not_found","entries":[]}'
      exit 0
    fi

    # Find all entries matching path (may have multiple versions)
    ENTRIES=$(jq -s --arg p "$QUERY_PATH" '[.[] | select(.path == $p)]' "$REGISTRY_FILE" 2>/dev/null || echo "[]")
    COUNT=$(echo "$ENTRIES" | jq 'length' 2>/dev/null || echo "0")

    if [ "$COUNT" -eq 0 ] || [ "$COUNT" = "0" ]; then
      echo '{"result":"not_found","entries":[]}'
    else
      jq -n --argjson entries "$ENTRIES" --argjson count "$COUNT" \
        '{result: "found", count: $count, entries: $entries}'
    fi
    ;;

  list)
    FILTER_PHASE="${1:-}"

    if [ ! -f "$REGISTRY_FILE" ]; then
      echo '{"result":"empty","entries":[]}'
      exit 0
    fi

    if [ -n "$FILTER_PHASE" ]; then
      ENTRIES=$(jq -s --argjson p "$FILTER_PHASE" '[.[] | select(.phase == $p)]' "$REGISTRY_FILE" 2>/dev/null || echo "[]")
    else
      ENTRIES=$(jq -s '.' "$REGISTRY_FILE" 2>/dev/null || echo "[]")
    fi

    COUNT=$(echo "$ENTRIES" | jq 'length' 2>/dev/null || echo "0")
    jq -n --argjson entries "$ENTRIES" --argjson count "$COUNT" \
      '{result: "ok", count: $count, entries: $entries}'
    ;;

  *)
    echo "{\"result\":\"error\",\"errors\":[\"unknown command: ${COMMAND}\"]}"
    ;;
esac
