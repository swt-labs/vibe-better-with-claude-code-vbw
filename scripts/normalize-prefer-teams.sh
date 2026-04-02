#!/usr/bin/env bash
set -u

# normalize-prefer-teams.sh — emit canonical prefer_teams values.
#
# Usage:
#   bash scripts/normalize-prefer-teams.sh [path/to/config.json]
#   bash scripts/normalize-prefer-teams.sh --value <raw-value>
#
# Canonical values:
#   always | auto | never
#
# Legacy normalization:
#   when_parallel -> auto
#   true          -> always
#   false/null    -> auto

read_raw_value() {
  local config_path="$1"

  if [ ! -f "$config_path" ] || ! command -v jq >/dev/null 2>&1; then
    echo "auto"
    return 0
  fi

  jq -r '.prefer_teams // "auto"' "$config_path" 2>/dev/null || echo "auto"
}

normalize_prefer_teams() {
  case "${1:-auto}" in
    ""|null|false|when_parallel)
      echo "auto"
      ;;
    true)
      echo "always"
      ;;
    always|auto|never)
      echo "$1"
      ;;
    *)
      # Intentionally preserve unknown values so callers can decide whether to
      # validate strictly or fail open.
      echo "$1"
      ;;
  esac
}

if [ "${1:-}" = "--value" ]; then
  shift
  normalize_prefer_teams "${1:-auto}"
  exit 0
fi

normalize_prefer_teams "$(read_raw_value "${1:-.vbw-planning/config.json}")"