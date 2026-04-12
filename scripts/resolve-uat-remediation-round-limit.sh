#!/usr/bin/env bash
set -u

# resolve-uat-remediation-round-limit.sh — normalize the UAT remediation round cap.
#
# Usage:
#   bash scripts/resolve-uat-remediation-round-limit.sh [path/to/config.json]
#     -> emits a positive integer when the cap is finite, or an empty string
#        when the effective behavior is unlimited.
#
#   bash scripts/resolve-uat-remediation-round-limit.sh --normalize-json <json-literal>
#     -> emits canonical JSON literal: false or positive integer.
#
#   bash scripts/resolve-uat-remediation-round-limit.sh --validate-input <value>
#     -> validates explicit /vbw:config input. Emits canonical JSON literal
#        false or positive integer. Exit 1 on invalid interactive input.
#
# Semantics:
#   - new key max_uat_remediation_rounds wins over legacy max_remediation_rounds
#   - absent key => unlimited
#   - false / 0 => unlimited
#   - positive integer => exact finite cap
#   - malformed persisted values => unlimited

usage() {
  echo "Usage: resolve-uat-remediation-round-limit.sh [config-path] | --normalize-json <json-literal> | --validate-input <value>" >&2
}

normalize_json_literal() {
  local raw="${1:-}"

  case "$raw" in
    ""|null|false|0)
      echo "false"
      return 0
      ;;
    true)
      echo "false"
      return 0
      ;;
  esac

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    if [ "$raw" -eq 0 ] 2>/dev/null; then
      echo "false"
    else
      echo "$((10#$raw))"
    fi
    return 0
  fi

  echo "false"
}

validate_input_value() {
  local raw="${1:-}"
  local normalized

  normalized=$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')

  case "$normalized" in
    false)
      echo "false"
      return 0
      ;;
    0)
      echo "false"
      return 0
      ;;
  esac

  if [[ "$normalized" =~ ^[0-9]+$ ]]; then
    if [ "$normalized" -eq 0 ] 2>/dev/null; then
      echo "false"
    else
      echo "$((10#$normalized))"
    fi
    return 0
  fi

  return 1
}

read_json_literal() {
  local config_path="$1"
  local key="$2"

  jq -c --arg key "$key" 'if has($key) then .[$key] else empty end' "$config_path" 2>/dev/null
}

resolve_from_config() {
  local config_path="${1:-.vbw-planning/config.json}"
  local raw canonical

  if ! command -v jq >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  if [ ! -f "$config_path" ] || ! jq empty "$config_path" >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  raw=$(read_json_literal "$config_path" "max_uat_remediation_rounds" || true)
  if [ -n "$raw" ]; then
    canonical=$(normalize_json_literal "$raw")
    if [ "$canonical" = "false" ]; then
      echo ""
    else
      echo "$canonical"
    fi
    return 0
  fi

  raw=$(read_json_literal "$config_path" "max_remediation_rounds" || true)
  if [ -n "$raw" ]; then
    canonical=$(normalize_json_literal "$raw")
    if [ "$canonical" = "false" ]; then
      echo ""
    else
      echo "$canonical"
    fi
    return 0
  fi

  echo ""
}

case "${1:-}" in
  --normalize-json)
    shift
    normalize_json_literal "${1:-}"
    ;;
  --validate-input)
    shift
    validate_input_value "${1:-}" || exit 1
    ;;
  --help|-h)
    usage
    exit 0
    ;;
  *)
    resolve_from_config "${1:-.vbw-planning/config.json}"
    ;;
esac