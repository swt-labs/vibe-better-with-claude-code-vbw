#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record,
# the approval state of its contract, and whether the code changed since proof.

cmd_next() {
  vbw_require_project
  local record hash approved=false changed=false legacy=false next
  record=$(record_read)
  hash=$(contract_hash "$record")
  contract_approved "$hash" && approved=true
  next_code_changed "$record" && changed=true
  # A VBW 1 plan not yet converted (docs/convert.md).
  [ -d "$VBW_ROOT/.vbw-planning" ] && ! printf '%s' "$record" | jq -e 'has("converted")' > /dev/null && legacy=true
  next=$(printf '%s' "$record" | jq -c --argjson approved "$approved" --arg contract "$hash" \
    --argjson code_changed "$changed" --argjson legacy "$legacy" -f "$VBW_LIB/next.jq")
  # The status line shows the last answer (docs/statusline.md).
  printf '%s\n' "$next" > "$VBW_RUNTIME/next.json.$$" && mv "$VBW_RUNTIME/next.json.$$" "$VBW_RUNTIME/next.json"
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$next"
  else
    printf '%s\n' "$next" | jq -r '"\(.action)\(if .gate then " (needs you)" else "" end): \(.instruction)"'
  fi
}

# True when the project's files differ from the ones the last proof ran on
# (vbw_code_tree: content, not commits, so committing proved work or the
# record never makes evidence stale). No evidence counts as no change: the
# evidence is already stale for lack of a proof.
next_code_changed() {
  local proved now
  proved=$(printf '%s' "$1" | jq -r '.evidence.tree // empty')
  [ -n "$proved" ] || return 1
  now=$(vbw_code_tree) || return 0
  [ "$now" != "$proved" ]
}
