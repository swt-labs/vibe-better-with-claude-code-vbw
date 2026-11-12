#!/usr/bin/env bats
# R191, phase P150 (L1): the kernel writes the road next to the step: into
# .vbw/runtime/next.json by vbw next, and into the running step's note
# (.vbw/runtime/step.json) by vbw run start, at every vbw plan done and at every
# proof unit that moves the step's end. A running step contributes its current end
# (moved when late), not its first estimate, so a step running later than usual
# moves the milestone's end by the same amount at once. Only the kernel writes
# these files. P1 is at standard here (vbw plan done asks no mutation breaks), so
# the fixture road is 500 (wave 1) + 10 (proof) + 300 (wave 2) + 20 (proof) + 100
# (QA P1) + 100 (QA P2) = 1030 s and no fix rounds (no finished standard phases,
# so the end is a rough guess, R270): after wave 1 the rest is 530 s.

load helper
load step-helper
load road-helper

setup() {
  vbw_setup
  road_project
  step_edit '.phases[0].tier = "standard"'
  ROAD_HIST_RUNS=5 road_hist
}
teardown() { vbw_teardown; }

# gap: the note's road end minus the step's end, in seconds.
gap() { jq -r '((.road.end | fromdateiso8601) - (.end | fromdateiso8601))' "$NOTE"; }

@test "R191: vbw next writes the road into next.json beside the step" {
  "$VBW" next --json > /dev/null
  jq -e '.step.kind == "build" and .road.seconds == 1030 and (.road.end | type == "string") and .road.rough == true and (.road.say | startswith("Milestone end: roughly 17 min"))' .vbw/runtime/next.json \
    || { cat .vbw/runtime/next.json; false; }
}

@test "R191: vbw run start writes the road into the note: the running wave's end plus the rest" {
  vbw_run run start build P1.1 P1.2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.kind == "build" and (.road | type == "object") and .road.seconds == 1030' "$NOTE" || { cat "$NOTE"; false; }
  [ "$(gap)" -eq 530 ] || { cat "$NOTE"; false; }
  [[ "$output" == *"Milestone end: roughly 17 min, until around"* ]] || { echo "$output"; false; }
}

@test "R191: a plan done on a late build moves the step's end and the milestone's end by the same amount, at once" {
  "$VBW" run start build P1.1 P1.2 > /dev/null
  step_back 1000
  local before
  before=$(jq -r '.road.end | fromdateiso8601' "$NOTE")
  step_finish P1.1 src/a.txt
  jq -e '.late == true and .parts.done == 1' "$NOTE" || { cat "$NOTE"; false; }
  [ "$(gap)" -eq 530 ] || { cat "$NOTE"; false; }
  jq -e --argjson b "$before" '(.road.end | fromdateiso8601) > $b' "$NOTE" || { cat "$NOTE"; false; }
  jq -e '.road.say | contains("Milestone end: ")' "$NOTE" || { cat "$NOTE"; false; }
}

@test "R191: a proof of its own carries the road in its note and moves it with each unit that makes it late" {
  mkdir -p tests
  cat > tests/snap.sh << 'SH'
jq -c . "$NOTE" >> "$SNAPS" 2> /dev/null || echo '{"missing": true}' >> "$SNAPS"
SH
  printf 'sleep 4\n' > tests/slow.sh
  SNAPS="$TEST_ROOT/snaps"
  export SNAPS
  step_edit '.plans[].status = "done" | .checks = [{id: "C1", req: "R1", run: ["sh", "tests/snap.sh"]},
    {id: "C2", req: "R1", run: ["sh", "tests/slow.sh"]}, {id: "C3", req: "R2", run: ["sh", "tests/snap.sh"]}]'
  git add -A && git commit -q -m "chore(vbw): slow checks"
  "$VBW" approve > /dev/null
  "$VBW" config set check_jobs 1 > /dev/null
  jq 'del(.steps[] | select(.kind == "proof"))' "$STEPS" > "$TEST_ROOT/h.json" && cp "$TEST_ROOT/h.json" "$STEPS"
  hist_proof '[{"name": "check:C1", "seconds": 1}, {"name": "check:C2", "seconds": 1}, {"name": "check:C3", "seconds": 1}]' 3 3
  runs_seed '{"check:C1": 1, "check:C2": 1, "check:C3": 1}'
  "$VBW" prove > /dev/null || true
  [ -s "$SNAPS" ] || { echo "no snapshot of the note was taken"; false; }
  jq -e 'select(.kind == "proof") | (.road | type == "object") and (.road.end | type == "string")' "$SNAPS" > /dev/null || { cat "$SNAPS"; false; }
  [ "$(jq -c 'select(.kind == "proof")' "$SNAPS" | wc -l | tr -d ' ')" -ge 2 ] || { cat "$SNAPS"; false; }
  local first last
  first=$(jq -c 'select(.kind == "proof")' "$SNAPS" | head -1)
  last=$(jq -c 'select(.kind == "proof")' "$SNAPS" | tail -1)
  jq -n --argjson a "$first" --argjson b "$last" -e '
    (($a.road.end | fromdateiso8601) - ($a.end | fromdateiso8601)) == (($b.road.end | fromdateiso8601) - ($b.end | fromdateiso8601))
    and ($b.end | fromdateiso8601) > ($a.end | fromdateiso8601) and $b.late == true' || { cat "$SNAPS"; false; }
}

@test "R191: the note's road is gone with the note when the run ends, and next.json keeps the last vbw next's" {
  "$VBW" next --json > /dev/null
  "$VBW" run start build P1.1 P1.2 > /dev/null
  "$VBW" run end > /dev/null
  [ ! -f "$NOTE" ]
  # vbw ship asks vbw next from inside the kernel (an inner caller): next.json is rewritten with the road kept.
  run "$VBW" ship
  [ "$status" -ne 0 ]
  jq -e '.road.seconds == 1030' .vbw/runtime/next.json || { cat .vbw/runtime/next.json; false; }
}

# R307 (T277): the road never puts the milestone's end before the end the current step shows.
# Each live note shape (a firm end, a late step with a rough range, a rough range with a
# typical figure) is handed to the road (road_compute) with the fixture's remaining pieces;
# its clock times must be at or after the step's own as step_words shows them.

# road_with NOTE: the road the kernel computes now for the live step NOTE (a JSON object
# whose times are seconds from now, turned into clock times here).
road_with() {
  local note
  note=$(jq -nc --argjson n "$1" '(now | floor) as $t | $n | with_entries(if (.key | test("^(end|end_low|end_high|end_typical|first_end|started_at)$")) and (.value | type == "number") then .value = ($t + .value | todateiso8601) else . end)')
  printf '%s\n' "$note" > "$TEST_ROOT/live.json"
  "$VBW" next --json > "$TEST_ROOT/next.json"
  # shellcheck disable=SC2016 # expanded by vbw_kernel
  vbw_kernel '. "$VBW_LIB/steps.sh"; road_compute "$(record_read)" "$(cat "$TEST_ROOT/next.json")" "$(cat "$TEST_ROOT/live.json")"'
}

# step_end NOTE_FILE WHICH: the step's own clock end in epoch seconds as its words show it:
# shown (the 'until around' time), low or high (the range's ends).
step_end() {
  jq -r --arg w "$2" '(.end | fromdateiso8601) as $e
    | ([(.end_low // .end | fromdateiso8601), $e] | min) as $lo | ([(.end_high // .end | fromdateiso8601), $e] | max) as $hi
    | if $w == "low" then $lo elif $w == "high" then $hi
      elif .late == true or .rough != true then $e
      else [[(.end_typical // .end | fromdateiso8601), $lo] | max, $hi] | min end' "$1"
}

# not_before ROAD: the road's until-around time, low and high are each at or after the step's.
not_before() {
  local shown
  shown=$(printf '%s' "$1" | jq -r 'if .rough then .end_typical else .end end | fromdateiso8601')
  [ "$shown" -ge "$(step_end "$TEST_ROOT/live.json" shown)" ] || { echo "the milestone ends before the step:"; echo "$1"; cat "$TEST_ROOT/live.json"; return 1; }
  if [ "$(printf '%s' "$1" | jq -r '.rough')" = true ]; then
    [ "$(printf '%s' "$1" | jq -r '.end_low | fromdateiso8601')" -ge "$(step_end "$TEST_ROOT/live.json" low)" ] \
      && [ "$(printf '%s' "$1" | jq -r '.end_high | fromdateiso8601')" -ge "$(step_end "$TEST_ROOT/live.json" high)" ] \
      || { echo "the milestone's range starts or ends before the step's:"; echo "$1"; cat "$TEST_ROOT/live.json"; return 1; }
  fi
}

@test "R307: T277's shape, a proof running late until around an hour from now: the milestone's end is not before it" {
  local r
  r=$(road_with '{"kind": "proof", "ids": [], "parts": {"done": 5, "total": 10}, "started_at": -1800, "first_end": -600,
    "end": 3600, "end_typical": 600, "end_low": 300, "end_high": 1200, "rough": true, "runs": 4, "late": true}')
  printf '%s' "$r" | jq -e 'type == "object" and .end != null' > /dev/null || { echo "$r"; false; }
  not_before "$r"
  # The duration the say names agrees with its end: the until-around time is now plus the typical seconds, or the seconds when firm.
  printf '%s' "$r" | jq -e '(now | floor) as $t | (if .rough then (.end_typical | fromdateiso8601) - .typical else (.end | fromdateiso8601) - .seconds end) - $t | fabs <= 60' > /dev/null || { echo "$r"; false; }
}

@test "R307: every live note shape: a firm end, a rough range and a typical with low and high give a milestone end at or after the step's own" {
  local n r
  for n in '{"kind": "proof", "ids": [], "parts": {"done": 0, "total": 10}, "started_at": -60, "first_end": 3000, "end": 3000, "rough": false, "late": false}' \
    '{"kind": "proof", "ids": [], "parts": {"done": 0, "total": 10}, "started_at": -60, "first_end": 3000, "end": 3000, "end_low": 600, "end_high": 4000, "rough": true, "runs": 2, "late": false}' \
    '{"kind": "proof", "ids": [], "parts": {"done": 0, "total": 10}, "started_at": -60, "first_end": 3000, "end": 3000, "end_typical": 900, "end_low": 600, "end_high": 4000, "rough": true, "runs": 3, "late": false}' \
    '{"kind": "proof", "ids": [], "parts": {"done": 0, "total": 10}, "started_at": -60, "first_end": 900, "end": 900, "end_typical": 3000, "end_low": 600, "end_high": 4000, "rough": true, "runs": 3, "late": false}'; do
    r=$(road_with "$n")
    printf '%s' "$r" | jq -e 'type == "object" and .end != null' > /dev/null || { echo "$n: $r"; false; }
    not_before "$r" || { echo "note: $n"; false; }
  done
}
