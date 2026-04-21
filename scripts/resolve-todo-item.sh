#!/usr/bin/env bash
# resolve-todo-item.sh — resolve a numbered todo selection to stable metadata.
#
# Usage:
#   bash resolve-todo-item.sh <N>
#   bash resolve-todo-item.sh <N> --session-snapshot [--require-unfiltered] [--validate-live]
#
# Output: JSON object with status, message/code on error, or the selected item metadata on success.
# Requires: jq, list-todos.sh, todo-lifecycle.sh in the same scripts/ directory
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N="${1:-}"
shift || true

USE_SESSION_SNAPSHOT="false"
REQUIRE_UNFILTERED="false"
VALIDATE_LIVE="false"

while [ $# -gt 0 ]; do
  case "$1" in
    --session-snapshot)
      USE_SESSION_SNAPSHOT="true"
      ;;
    --require-unfiltered)
      REQUIRE_UNFILTERED="true"
      ;;
    --validate-live)
      VALIDATE_LIVE="true"
      ;;
    *)
      jq -n --arg message "Unknown option: $1" '{status:"error", code:"usage", message:$message}'
      exit 0
      ;;
  esac
  shift || true
done

if [ -z "$N" ]; then
  printf '{"status":"error","code":"usage","message":"Usage: resolve-todo-item.sh <N> [--session-snapshot] [--require-unfiltered] [--validate-live]"}\n'
  exit 0
fi

if ! [[ "$N" =~ ^[0-9]+$ ]]; then
  jq -n --arg message "Not a number: $N" '{status:"error", code:"not_a_number", message:$message}'
  exit 0
fi

N=$((10#$N))

select_from_live_list() {
  local output_json status_val count idx
  output_json=$(bash "$SCRIPT_DIR/list-todos.sh" 2>/dev/null || true)
  status_val=$(printf '%s' "$output_json" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$status_val" != "ok" ]; then
    local msg
    msg=$(printf '%s' "$output_json" | jq -r '.message // .display // "Unknown error"' 2>/dev/null || echo 'Unknown error')
    jq -n --arg message "$msg" '{status:"error", code:"live_list_error", message:$message}'
    return 0
  fi

  count=$(printf '%s' "$output_json" | jq '.items | length')
  if [ "$N" -lt 1 ] || [ "$N" -gt "$count" ]; then
    jq -n --arg message "Invalid selection — only items 1-${count} exist." '{status:"error", code:"invalid_selection", message:$message}'
    return 0
  fi

  idx=$((N - 1))
  printf '%s' "$output_json" | jq -c --argjson idx "$idx" --argjson num "$N" '
    .items[$idx] + {status:"ok", num:$num, selection_source:"live"}
  '
}

select_from_snapshot() {
  local args=("$N")
  if [ "$REQUIRE_UNFILTERED" = "true" ]; then
    args=("$N" --require-unfiltered)
  fi
  bash "$SCRIPT_DIR/todo-lifecycle.sh" snapshot-select "${args[@]}"
}

selected_json=""
if [ "$USE_SESSION_SNAPSHOT" = "true" ]; then
  selected_json=$(select_from_snapshot)
else
  selected_json=$(select_from_live_list)
fi

selected_status=$(printf '%s' "$selected_json" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
if [ "$selected_status" != "ok" ]; then
  printf '%s\n' "$selected_json"
  exit 0
fi

if [ "$VALIDATE_LIVE" = "true" ]; then
  selection_source="live"
  if [ "$USE_SESSION_SNAPSHOT" = "true" ]; then
    selection_source="snapshot"
  fi
  validated_json=$(printf '%s' "$selected_json" | bash "$SCRIPT_DIR/todo-lifecycle.sh" validate-item)
  validated_status=$(printf '%s' "$validated_json" | jq -r '.status // "error"' 2>/dev/null || echo 'error')
  if [ "$validated_status" != "ok" ]; then
    printf '%s\n' "$validated_json"
    exit 0
  fi
  selected_json=$(printf '%s' "$validated_json" | jq -c --argjson num "$N" --arg source "$selection_source" '
    . + {status:"ok", num:$num, selection_source:(if $source == "snapshot" then "snapshot" else "live" end)}
  ')
fi

printf '%s\n' "$selected_json"
