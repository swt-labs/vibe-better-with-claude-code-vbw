#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record,
# the approval state of its contract, and whether the code changed since proof.

cmd_next() {
  vbw_require_project
  local record hash tracked code approved=false changed=false legacy=false next
  record=$(record_read)
  hash=$(contract_hash "$record")
  contract_approved "$hash" && commands_approved "$record" && approved=true
  next_code_changed "$record" && changed=true
  # A VBW 1 plan not yet converted (docs/convert.md).
  [ -d "$VBW_ROOT/.vbw-planning" ] && ! printf '%s' "$record" | jq -e 'has("converted")' > /dev/null && legacy=true
  tracked=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | tr -cd '\0' | wc -c | tr -d ' ')
  # Code: tracked files outside .vbw/ that are not markdown or text.
  code=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | jq -Rs '[split("\u0000")[] | select(length > 0 and ((startswith(".vbw/") or test("\\.(md|markdown|txt)$")) | not))] | length')
  next=$(printf '%s' "$record" | jq -c --argjson tracked "{\"tracked\":${tracked:-0},\"code\":${code:-0}}" --argjson approved "$approved" --arg contract "$hash" \
    --argjson code_changed "$changed" --argjson legacy "$legacy" --arg session "$(vbw_session)" --slurpfile tiers "$VBW_LIB/tiers.json" "$VBW_JQ_DEFS$(cat "$VBW_LIB/next.jq")")
  # The status line shows the last answer (docs/statusline.md).
  printf '%s\n' "$next" > "$VBW_RUNTIME/next.json.$$" && mv "$VBW_RUNTIME/next.json.$$" "$VBW_RUNTIME/next.json"
  if [ "${1:-}" = "--json" ]; then
    printf '%s\n' "$next"
  else
    printf '%s\n' "$next" | jq -r '"\(.action)\(if .gate then " (needs you)" else "" end): \(.instruction)"'
  fi
}

# True when the project's files differ from the ones the last proof saw: the
# working folder (vbw_code_tree: content, so committing VBW's record never
# makes evidence stale) or the committed code the checks ran on (head: an edit
# proved while uncommitted and committed later was never proved). No evidence
# counts as no change: the evidence is already stale for lack of a proof.
next_code_changed() {
  local proved head now
  proved=$(printf '%s' "$1" | jq -r '.evidence.tree // empty')
  [ -n "$proved" ] || return 1
  now=$(vbw_code_tree) || return 0
  [ "$now" = "$proved" ] || return 0
  head=$(printf '%s' "$1" | jq -r '.evidence.head // empty')
  [ -n "$head" ] || return 1
  now=$(vbw_head_tree) || return 0
  [ "$now" != "$head" ]
}
