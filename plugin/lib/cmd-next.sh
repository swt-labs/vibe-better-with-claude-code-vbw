#!/usr/bin/env bash
# vbw next [--json]: the next lifecycle step (docs/next.md), from the record,
# the approval state of its contract, and whether the code changed since proof.

# shellcheck source=interview.sh
. "$VBW_LIB/interview.sh"
# shellcheck source=qa-inputs.sh
. "$VBW_LIB/qa-inputs.sh"
# shellcheck source=effort.sh
. "$VBW_LIB/effort.sh"

# qa_state RECORD [DIGESTS]: lib/qa.jq's answer (closure, recheck, standing, problems).
# The one judgment of whether a pass stands; a pass of another fingerprint
# version is first fingerprinted again at its own commit (qa_settle).
qa_state() {
  local d="${2:-}"
  [ -n "$d" ] || d=$(qa_digests "$1")
  qa_settle "$1" "$d"
  jq -c --argjson inputs "$d" --argjson cache "$(qa_cache_read)" --argjson fpv "$QA_FP_VERSION" -f "$VBW_LIB/qa.jq" <<< "$1"
}

# qa_combined RECORD [DIGESTS]: {Pn: the phase's current fingerprint}: what a
# standing pass holds in qa.tree (D91). A pass that stands across a fingerprint
# version is held by the qa.tree it has.
qa_combined() {
  local d="${2:-}"
  [ -n "$d" ] || d=$(qa_digests "$1")
  qa_state "$1" "$d" | jq -c --argjson d "$d" --argjson r "$1" '. as $s | $d | map_values(.combined)
    + ([$r.phases[] | select(.id as $i | $s.standing | index($i)) | select(.qa.tree != null) | {(.id): .qa.tree}] | add // {})'
}

cmd_next() {
  vbw_require_project
  local effort record hash counts approved=false changed=false legacy=false next qa waiting
  record=$(record_read)
  hash=$(contract_hash "$record")
  # Check files edited since the approval wait: the build goes on, the one approval comes before proof.
  waiting=$(contract_waiting "$record") && commands_approved "$record" && approved=true
  next_code_changed "$record" && changed=true
  # A VBW 1 plan not yet converted (docs/convert.md).
  [ -d "$VBW_ROOT/.vbw-planning" ] && ! printf '%s' "$record" | jq -e 'has("converted") or .project.legacy.choice == "fresh"' > /dev/null && legacy=true
  # Tracked files, and of those the code: outside .vbw/ and not documentation (is_doc).
  counts=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | jq -Rs "$VBW_JQ_DEFS"'[split("\u0000")[] | select(length > 0)]
    | {tracked: length, code: ([.[] | select((startswith(".vbw/") or is_doc) | not)] | length)}')
  qa=$(qa_state "$record")
  # A plan that names a plan or phase that is not there cannot be judged.
  jq -e '.problems | any(.[]; contains("does not exist")) | not' <<< "$qa" > /dev/null || vbw_die "$(jq -r '.problems | join("; ")' <<< "$qa")"
  # The profile's effort table; a wrong table stops here, before any answer.
  effort=$(effort_table "$(printf '%s' "$record" | jq -r '.settings.profile')") || exit 1
  next=$(printf '%s' "$record" | jq -c --argjson effort "$effort" --argjson tracked "$counts" --argjson approved "$approved" --arg waiting "$waiting" --arg contract "$hash" \
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
