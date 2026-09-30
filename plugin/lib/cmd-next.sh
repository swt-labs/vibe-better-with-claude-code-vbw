#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record only.

cmd_next() {
  vbw_require_project
  local next
  next=$(record_read | jq -c -f "$VBW_LIB/next.jq")
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$next"
  else
    printf '%s\n' "$next" | jq -r '"\(.action)\(if .gate then " (needs you)" else "" end): \(.instruction)"'
  fi
}
