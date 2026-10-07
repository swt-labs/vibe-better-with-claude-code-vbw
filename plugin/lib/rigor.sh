#!/usr/bin/env bash
# Adaptive rigor: the signals of lib/rigor.jq plus the file facts jq cannot read.

# rigor_assess [PHASE_ID...] < RECORD_JSON: a JSON array [{id, tier, floor,
# reasons}] for the given phases (default: the current milestone's phases).
# Reads existence and size of the planned regular files under $VBW_ROOT;
# directory entries and missing files are not facts.
rigor_assess() {
  local record paths=() p facts ids='null' tracked guarded
  record=$(cat)
  [ $# -eq 0 ] || ids=$(printf '%s\n' "$@" | jq -Rnc '[inputs]')
  while IFS= read -r -d '' p; do
    paths+=("$p")
  done < <(printf '%s' "$record" | jq -j --argjson ids "$ids" '
    . as $r | ($ids // [$r.phases[] | select(.milestone == $r.milestone.id) | .id]) as $want
    | [$r.plans[] | select(.phase as $i | $want | index($i)) | .files[]] | unique[] | . + "\u0000"')
  tracked=$(git -C "$VBW_ROOT" ls-files -z 2> /dev/null | tr -cd '\000' | wc -c | tr -d ' ')
  facts='{}'
  for p in ${paths[@]+"${paths[@]}"}; do
    [ -f "$VBW_ROOT/$p" ] && [ ! -L "$VBW_ROOT/$p" ] || continue
    facts=$(printf '%s' "$facts" | jq -c --arg p "$p" --argjson n "$(wc -c < "$VBW_ROOT/$p" | tr -d ' ')" '.[$p] = $n')
  done
  guarded=$(rigor_guarded "$record")
  printf '%s' "$record" | jq -c --argjson facts "$facts" --argjson guarded "$guarded" --argjson tracked "${tracked:-0}" --argjson ids "$ids" "$VBW_JQ_DEFS$(cat "$VBW_LIB/rigor.jq")"
}

# rigor_guarded RECORD_JSON: a JSON array [{req, checks}] of the guarded
# requirements: [auto] ones with at least one check where every check is
# approved, that is, equal in definition and in the digest of each file to
# the last approved contract of this clone. No approved contract, or a
# changed or missing check or file, means not guarded.
rigor_guarded() {
  local old="$VBW_RUNTIME/approved-contract.json" f digests='{}'
  [ -f "$old" ] && jq -e . "$old" > /dev/null 2>&1 || { printf '[]'; return 0; }
  while IFS= read -r -d '' f; do
    [ -f "$VBW_ROOT/$f" ] && [ ! -L "$VBW_ROOT/$f" ] || continue
    digests=$(printf '%s' "$digests" | jq -c --arg f "$f" --arg d "$(vbw_sha256 < "$VBW_ROOT/$f")" '.[$f] = $d')
  done < <(printf '%s' "$1" | jq -j '[.checks[].files // [] | .[]] | unique[] | . + "\u0000"')
  printf '%s' "$1" | jq -c --slurpfile old "$old" --argjson now "$digests" '
    $old[0] as $o
    | def approved: . as $c | $o.checks[$c.id] == $c
        and all(($c.files // [])[]; . as $f | ($now[$f] != null and $o.files[$f] == $now[$f]));
    . as $r
    | [ $r.requirements[] | select(.proof == "auto") | .id as $q
        | [$r.checks[] | select(.req == $q)] as $cs
        | select(($cs | length) > 0 and all($cs[]; approved))
        | {req: $q, checks: [$cs[].id]} ]' 2> /dev/null || printf '[]'
}

# rigor_escalate PHASE REASON [TIER]: raise a phase's tier (one step, or to TIER)
# and record why; the single way a trigger raises a tier. Never lowers a tier.
# Takes the record lock itself: call it with the lock released.
rigor_escalate() {
  record_update "$VBW_JQ_DEFS"'escalate_phases([$p]; (if $to == "" then null else $to end); $why; $at)' \
    --arg p "$1" --arg why "$2" --arg to "${3:-}" --arg at "$(vbw_now)"
}
