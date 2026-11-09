#!/usr/bin/env bash
# The road (R191, docs/next.md): the end of the milestone, one clock time. Sourced
# by steps.sh; sources nothing itself (it needs steps.sh's step_history_file and
# VBW_STEP_DEFS, which are loaded where it is).

# road_compute RECORD_JSON NEXT_JSON NOTE_JSON: print the road, {seconds, end,
# rounds, basis, say}, or null. NOTE_JSON is the live step's note, empty when no
# step is live. One jq run (lib/road.jq): every piece's expected seconds comes
# from lib/steps-expect.jq's ladders, wrapped as `expect($kind; $size)` in front
# of the program, and the record, the history, the run times (run-times.json
# beside the run store, step_expect: never the store itself), vbw next's answer
# and the note reach it by --slurpfile only. steps-expect.jq reads its size as
# step_expect slurps it, $size[0], so the wrapper hands it [$size]. A missing,
# damaged or unreadable history only means no end time yet.
road_expect_defs() {
  printf 'def expect($kind; $s): [$s] as $size |\n%s;\n' "$(cat "$VBW_LIB/steps-expect.jq")"
}

road_compute() {
  local record="$1" next="$2" note="${3:-}" file runs expect out
  [ -f "$VBW_LIB/road.jq" ] && [ -f "$VBW_LIB/steps-expect.jq" ] || { echo null; return 0; }
  [ -n "$note" ] || note=null
  file=$(step_history_file)
  runs=""
  [ -z "$file" ] || runs="$(dirname "$file")/run-times.json"
  expect=$(road_expect_defs)
  out=$(jq -n -c --slurpfile rec <(printf '%s' "$record") \
    --slurpfile h <(jq -c 'select(type == "object" and (.steps | type) == "array")' "$file" 2> /dev/null) \
    --slurpfile runs <(jq -c 'select(type == "object" and (.runs | type) == "object")' "$runs" 2> /dev/null) \
    --slurpfile next <(printf '%s' "$next") --slurpfile note <(printf '%s' "$note") \
    "$VBW_JQ_DEFS$VBW_STEP_DEFS$expect$(cat "$VBW_LIB/road.jq")" 2> /dev/null) || out=null
  vbw_out '%s\n' "${out:-null}"
}
