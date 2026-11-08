#!/usr/bin/env bats
# R191, phase P150 (L1): the kernel writes the road next to the step: into
# .vbw/runtime/next.json by vbw next, and into the running step's note
# (.vbw/runtime/step.json) by vbw run start, at every vbw plan done and at every
# proof unit that moves the step's end. A running step contributes its current end
# (moved when late), not its first estimate, so a step running later than usual
# moves the milestone's end by the same amount at once. Only the kernel writes
# these files. P1 is at standard here (vbw plan done asks no mutation breaks), so
# the fixture road is 500 (wave 1) + 10 (proof) + 300 (wave 2) + 20 (proof) + 100
# (QA P1) + 100 (QA P2) = 1030 s and no fix rounds (no finished standard phases):
# after wave 1 the rest is 530 s.

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
  jq -e '.step.kind == "build" and .road.seconds == 1030 and (.road.end | type == "string") and (.road.say | startswith("Milestone end: about 17 min"))' .vbw/runtime/next.json \
    || { cat .vbw/runtime/next.json; false; }
}

@test "R191: vbw run start writes the road into the note: the running wave's end plus the rest" {
  vbw_run run start build P1.1 P1.2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '.kind == "build" and (.road | type == "object") and .road.seconds == 1030' "$NOTE" || { cat "$NOTE"; false; }
  [ "$(gap)" -eq 530 ] || { cat "$NOTE"; false; }
  [[ "$output" == *"Milestone end: about 17 min, until around"* ]] || { echo "$output"; false; }
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
