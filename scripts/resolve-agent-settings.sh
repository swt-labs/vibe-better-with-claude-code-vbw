#!/usr/bin/env bash
# resolve-agent-settings.sh - Resolve model + max-turns for one agent in one call.
#
# Usage:
#   resolve-agent-settings.sh <agent-name> <config-path> <profiles-path> [effort]
#
# Output:
#   Shell-safe assignments suitable for eval:
#     RESOLVED_AGENT='dev'
#     RESOLVED_MODEL='opus'
#     RESOLVED_MAX_TURNS='75'
#     RESOLVED_EFFORT='balanced'
#
# Notes:
# - If [effort] is omitted or invalid, falls back to config.effort, then balanced.
# - RESOLVED_MAX_TURNS may be empty when turn budgets are disabled/unlimited.

set -euo pipefail

usage() {
  echo "Usage: resolve-agent-settings.sh <agent-name> <config-path> <profiles-path> [effort]" >&2
}

normalize_effort() {
  local raw
  raw=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')

  case "$raw" in
    thorough|balanced|fast|turbo)
      printf '%s' "$raw"
      ;;
    high)
      printf 'thorough'
      ;;
    medium)
      printf 'balanced'
      ;;
    low)
      printf 'turbo'
      ;;
    "")
      printf ''
      ;;
    *)
      return 1
      ;;
  esac
}

resolve_effective_effort() {
  local config_path="$1"
  local effort_input="${2:-}"
  local normalized=""
  local config_effort=""

  if normalized=$(normalize_effort "$effort_input" 2>/dev/null); then
    if [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
  fi

  if [ -f "$config_path" ] && command -v jq >/dev/null 2>&1 && jq empty "$config_path" >/dev/null 2>&1; then
    config_effort=$(jq -r '.effort // empty' "$config_path" 2>/dev/null || echo "")
    if normalized=$(normalize_effort "$config_effort" 2>/dev/null); then
      if [ -n "$normalized" ]; then
        printf '%s' "$normalized"
        return 0
      fi
    fi
  fi

  printf 'balanced'
}

shell_quote() {
  local value="$1"
  value=$(printf '%s' "$value" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$value"
}

emit_assignment() {
  local name="$1"
  local value="$2"
  printf '%s=%s\n' "$name" "$(shell_quote "$value")"
}

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT="$1"
CONFIG_PATH="$2"
PROFILES_PATH="$3"
EFFORT_INPUT="${4:-}"

MODEL=$(bash "$SCRIPT_DIR/resolve-agent-model.sh" "$AGENT" "$CONFIG_PATH" "$PROFILES_PATH")
EFFECTIVE_EFFORT=$(resolve_effective_effort "$CONFIG_PATH" "$EFFORT_INPUT")
MAX_TURNS=$(bash "$SCRIPT_DIR/resolve-agent-max-turns.sh" "$AGENT" "$CONFIG_PATH" "$EFFECTIVE_EFFORT")

emit_assignment RESOLVED_AGENT "$AGENT"
emit_assignment RESOLVED_MODEL "$MODEL"
emit_assignment RESOLVED_MAX_TURNS "$MAX_TURNS"
emit_assignment RESOLVED_EFFORT "$EFFECTIVE_EFFORT"
