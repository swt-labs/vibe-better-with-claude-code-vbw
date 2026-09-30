#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record and
# the approval state of its contract.

cmd_next() {
  vbw_require_project
  local record hash approved=false next
  record=$(record_read)
  hash=$(contract_hash "$record")
  contract_approved "$hash" && approved=true
  next=$(printf '%s' "$record" | jq -c --argjson approved "$approved" --arg contract "$hash" -f "$VBW_LIB/next.jq")
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$next"
  else
    printf '%s\n' "$next" | jq -r '"\(.action)\(if .gate then " (needs you)" else "" end): \(.instruction)"'
  fi
}
