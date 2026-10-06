#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record,
# the approval state of its contract, and whether the code changed since proof.

# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"
# shellcheck source=qa-inputs.sh
. "$VBW_LIB/qa-inputs.sh"

# qa_combined RECORD: {Pn: combined digest}, what a standing pass holds in qa.tree (D91).
qa_combined() { qa_digests "$1" | jq -c 'map_values(.combined)'; }

# qa_state RECORD: lib/qa.jq's answer (closure, recheck, standing, problems).
qa_state() { jq -c --argjson inputs "$(qa_digests "$1")" --argjson cache "$(qa_cache_read)" -f "$VBW_LIB/qa.jq" <<< "$1"; }

cmd_next() {
  vbw_require_project
  local record hash counts approved=false changed=false legacy=false next qa waiting
  record=$(record_read)
  hash=$(contract_hash "$record")
  # Check files edited since the approval wait: the build goes on, the one approval comes before proof.
  waiting=$(contract_waiting "$record") && commands_approved "$record" && approved=true
  next_code_changed "$record" && changed=true
  # A VBW 1 plan not yet converted (docs/convert.md).
  [ -d "$VBW_ROOT/.vbw-planning" ] && ! printf '%s' "$record" | jq -e 'has("converted") or .project.legacy.choice == "fresh"' > /dev/null && legacy=true
  # Tracked files, and of those the code: outside .vbw/ and not markdown or text.
  counts=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | jq -Rs '[split("\u0000")[] | select(length > 0)]
    | {tracked: length, code: ([.[] | select((startswith(".vbw/") or test("\\.(md|markdown|txt)$")) | not)] | length)}')
  qa=$(qa_state "$record")
  # A plan that names a plan or phase that is not there cannot be judged.
  jq -e '.problems | any(.[]; contains("does not exist")) | not' <<< "$qa" > /dev/null || vbw_die "$(jq -r '.problems | join("; ")' <<< "$qa")"
  next=$(printf '%s' "$record" | jq -c --argjson tracked "$counts" --argjson approved "$approved" --arg waiting "$waiting" --arg contract "$hash" \
    --argjson code_changed "$changed" --argjson legacy "$legacy" --argjson qa "$qa" --argjson profile "$(interview_effective "$record")" --arg session "$(vbw_session)" --slurpfile tiers "$VBW_LIB/tiers.json" "$VBW_JQ_DEFS$(cat "$VBW_LIB/next.jq")")
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
