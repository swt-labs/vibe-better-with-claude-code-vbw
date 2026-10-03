#!/usr/bin/env bash
# Adaptive rigor: the signals of lib/rigor.jq plus the file facts jq cannot read.

# rigor_assess [PHASE_ID...] < RECORD_JSON: a JSON array [{id, tier, floor,
# reasons}] for the given phases (default: the current milestone's phases).
# Reads existence and size of the planned regular files under $VBW_ROOT;
# directory entries and missing files are not facts.
rigor_assess() {
  local record paths=() p facts ids='null'
  record=$(cat)
  [ $# -eq 0 ] || ids=$(printf '%s\n' "$@" | jq -Rnc '[inputs]')
  while IFS= read -r -d '' p; do
    paths+=("$p")
  done < <(printf '%s' "$record" | jq -j --argjson ids "$ids" '
    . as $r | ($ids // [$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $want
    | [$r.plans[] | select(.phase as $i | $want | index($i)) | .files[]] | unique[] | . + "\u0000"')
  facts='{}'
  for p in ${paths[@]+"${paths[@]}"}; do
    [ -f "$VBW_ROOT/$p" ] && [ ! -L "$VBW_ROOT/$p" ] || continue
    facts=$(printf '%s' "$facts" | jq -c --arg p "$p" --argjson n "$(wc -c < "$VBW_ROOT/$p" | tr -d ' ')" '.[$p] = $n')
  done
  printf '%s' "$record" | jq -c --argjson facts "$facts" --argjson ids "$ids" "$VBW_JQ_DEFS$(cat "$VBW_LIB/rigor.jq")"
}

# rigor_escalate PHASE REASON [TIER]: raise a phase's tier (one step, or to TIER)
# and record why; the single way a trigger raises a tier. Never lowers a tier.
# Takes the record lock itself: call it with the lock released.
rigor_escalate() {
  record_update "$VBW_JQ_DEFS"'escalate_phases([$p]; (if $to == "" then null else $to end); $why; $at)' \
    --arg p "$1" --arg why "$2" --arg to "${3:-}" --arg at "$(vbw_now)"
}
